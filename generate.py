#!/usr/bin/env python3
"""ランダムテストの入力を1ケース生成して標準出力に書く。

使い方: python3 generate.py [シード]
シードが同じなら同じケースが出る。問題ごとに下の gen() を書き換える。
"""
import random
from random import randint
import sys


def gen():
    # 例: 今の main.cpp の入力形式（N と 数列 A）
    # 手計算で追える小さいサイズにしておくと、相違の原因を調べやすい
    N = 0
    while 1:
        N = randint(2,8)
        if N%2 == 0:
            break
    
    A = [randint(1, 20) for _ in range(N)]
    A.sort()  # 問題の制約が A の昇順を保証しないなら消す

    print(N)
    print(*A)


if __name__ == "__main__":
    if len(sys.argv) > 1:
        random.seed(int(sys.argv[1]))
    gen()
