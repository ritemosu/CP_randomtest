#!/bin/bash
# ランダムテスト: generate.py の入力で ../main.cpp と naive.cpp の出力を比べる
#
# 使い方: ./randomtest/run.sh [-k] [回数=1000] [開始シード=1]
#         ./randomtest/run.sh --clean   failed/ と .cache/ を消す（問題を変えるときに）
#
#   -k  最初の失敗で止まらず、失敗ケースを集め続ける
#
# failed/ に保存したケースは毎回最初に再テストする。
# .cache/ にはコンパイル結果と naive の出力を置く。

cd "$(dirname "$0")" || exit 2
shopt -s nullglob

MAIN_SRC=../main.cpp
NAIVE_SRC=naive.cpp
TIME_LIMIT=5 # 1ケースあたりの秒数

# build.sh と同じフラグに、バグ検出用のサニタイザを足したもの
CXX_FLAGS="-std=gnu++20 -O2 -Wall -Wextra -I../ac-library -fsanitize=address,undefined -fno-sanitize-recover=all"
export ASAN_OPTIONS=detect_leaks=0

FAILED=failed
CACHE=.cache
WORK=$CACHE/work

KEEP_GOING=0
case "$1" in
    --clean)
        rm -rf "$FAILED" "$CACHE"
        echo "failed/ と .cache/ を消しました"
        exit 0
        ;;
    -k)
        KEEP_GOING=1
        shift
        ;;
esac
COUNT="${1:-1000}"
START_SEED="${2:-1}"

mkdir -p "$FAILED" "$CACHE/bin" "$CACHE/naive" "$WORK"

# ソースとフラグのハッシュでコンパイル結果を再利用する
# （#include 先の自作ヘッダの変更は検知しない）
# BUILD_KEY に結果のキーを入れる。バイナリは $CACHE/bin/<name>-<key>
build() {
    local name="$1" src="$2" link=""
    BUILD_KEY=$( { echo "$CXX_FLAGS"; cat "$src"; } | sha256sum | cut -c1-16 )
    local bin="$CACHE/bin/$name-$BUILD_KEY"
    [ -x "$bin" ] && return 0

    grep -q "gmpxx.h" "$src" && link="-lgmpxx -lgmp"
    echo "compiling $src ..."
    # shellcheck disable=SC2086
    g++ $CXX_FLAGS "$src" -o "$bin" $link || {
        echo "コンパイル失敗: $src"
        exit 2
    }
    # 古いバイナリは消す
    local old
    for old in "$CACHE/bin/$name"-*; do
        [ "$old" = "$bin" ] || rm -f "$old"
    done
}

build main "$MAIN_SRC"
MAIN_BIN="$CACHE/bin/main-$BUILD_KEY"
build naive "$NAIVE_SRC"
NAIVE_BIN="$CACHE/bin/naive-$BUILD_KEY"

# naive の出力キャッシュは naive.cpp が変わったら作り直す
NAIVE_CACHE="$CACHE/naive/$BUILD_KEY"
for old in "$CACHE/naive"/*; do
    [ "$old" = "$NAIVE_CACHE" ] || rm -rf "$old"
done
mkdir -p "$NAIVE_CACHE"

# 1プログラムを実行する。結果は 0=正常 / 1=RE / 2=TLE
exec_case() {
    local name="$1" bin="$2" status
    timeout "$TIME_LIMIT" "$bin" < "$WORK/in.txt" > "$WORK/$name.out" 2> "$WORK/$name.err"
    status=$?
    [ "$status" -eq 0 ] && return 0
    [ "$status" -eq 124 ] && return 2
    return 1
}

# $WORK/in.txt を判定して VERDICT に AC/WA/RE/TLE/naive-RE/naive-TLE を入れる
judge() {
    rm -f "$WORK"/main.* "$WORK"/naive.* "$WORK/diff.txt"
    INPUT_HASH=$(sha256sum < "$WORK/in.txt" | cut -c1-12)

    exec_case main "$MAIN_BIN"
    case $? in
        1) VERDICT=RE; return ;;
        2) VERDICT=TLE; return ;;
    esac

    local cached="$NAIVE_CACHE/$INPUT_HASH.out"
    if [ -f "$cached" ]; then
        cp "$cached" "$WORK/naive.out"
        CACHE_HITS=$((CACHE_HITS + 1))
    else
        exec_case naive "$NAIVE_BIN"
        case $? in
            1) VERDICT=naive-RE; return ;;
            2) VERDICT=naive-TLE; return ;;
        esac
        cp "$WORK/naive.out" "$cached"
    fi

    # 行末の空白の違いは無視する
    if diff -Z "$WORK/main.out" "$WORK/naive.out" > "$WORK/diff.txt"; then
        VERDICT=AC
    else
        VERDICT=WA
    fi
}

# 今のケースを failed/<判定>_seed<シード>_<入力ハッシュ>/ に保存する
save_case() {
    local seed="$1" old file
    for old in "$FAILED"/*_"$INPUT_HASH"; do
        rm -rf "$old"
    done
    SAVED_DIR="$FAILED/${VERDICT}_seed${seed}_$INPUT_HASH"
    mkdir -p "$SAVED_DIR"
    for file in in.txt main.out naive.out main.err naive.err diff.txt; do
        # 空のログは保存しない（in.txt と出力は空でも残す）
        case "$file" in
            *.err | diff.txt) [ -s "$WORK/$file" ] || continue ;;
        esac
        [ -f "$WORK/$file" ] && cp "$WORK/$file" "$SAVED_DIR/"
    done
}

show_file() {
    [ -f "$2" ] || return 0
    echo "--- $1 ---"
    head -n 30 "$2"
    [ "$(wc -l < "$2")" -gt 30 ] && echo "...(省略)"
    return 0
}

# 失敗内容を表示する。-k のときは1行だけ
report() {
    echo
    if [ "$KEEP_GOING" -eq 1 ]; then
        echo "[$VERDICT] $SAVED_DIR"
        return
    fi
    echo "=== $VERDICT ==="
    show_file "入力" "$SAVED_DIR/in.txt"
    show_file "main の出力" "$SAVED_DIR/main.out"
    show_file "naive の出力" "$SAVED_DIR/naive.out"
    show_file "diff (< main / > naive)" "$SAVED_DIR/diff.txt"
    show_file "main の標準エラー" "$SAVED_DIR/main.err"
    show_file "naive の標準エラー" "$SAVED_DIR/naive.err"
    echo
    echo "保存先: randomtest/$SAVED_DIR"
    exit 1
}

FAIL_COUNT=0
CACHE_HITS=0

# 保存済みの失敗ケースを先に再テストする
saved_dirs=("$FAILED"/*/)
if [ "${#saved_dirs[@]}" -gt 0 ]; then
    passed=0
    for dir in "${saved_dirs[@]}"; do
        dir="${dir%/}"
        seed="${dir##*_seed}"
        seed="${seed%_*}"
        cp "$dir/in.txt" "$WORK/in.txt"
        judge
        if [ "$VERDICT" = AC ]; then
            passed=$((passed + 1))
        else
            save_case "$seed"
            FAIL_COUNT=$((FAIL_COUNT + 1))
            echo "保存済みケースがまだ失敗しています（問題を変えたなら --clean で消せます）"
            report
        fi
    done
    echo "保存済みケース: ${passed}/${#saved_dirs[@]} 通過"
fi

for ((i = 0; i < COUNT; i++)); do
    seed=$((START_SEED + i))
    printf '\rseed=%d (%d/%d)' "$seed" "$((i + 1))" "$COUNT"

    python3 generate.py "$seed" > "$WORK/in.txt" || {
        echo
        echo "generate.py が失敗しました (seed=$seed)"
        exit 2
    }
    # 保存済みのケースは上で再テスト済み
    known=("$FAILED"/*_"$(sha256sum < "$WORK/in.txt" | cut -c1-12)")
    [ "${#known[@]}" -gt 0 ] && continue

    judge
    if [ "$VERDICT" != AC ]; then
        save_case "$seed"
        FAIL_COUNT=$((FAIL_COUNT + 1))
        report
    fi
done

echo
echo "naive の出力キャッシュ利用: ${CACHE_HITS} 件"
if [ "$FAIL_COUNT" -gt 0 ]; then
    echo "NG: ${FAIL_COUNT} ケース失敗（randomtest/$FAILED/ に保存）"
    exit 1
fi
echo "OK: 失敗はありません"
