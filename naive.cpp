#include <bits/stdc++.h>
using namespace std;
using ll = long long;
#define rep(i, n) for (int i = 0; i < (n); ++i)
#define all(a) a.begin(),a.end()
#define rall(a) a.rbegin(),a.rend()

// #error "naive.cpp に愚直解を書いて、この行を消してください"

int main(){
    // 全探索など、計算量を気にせず確実に正しい解法を書く

    int N; cin >> N;
    vector<int> A(N);
    rep(i,N) cin >> A[i];

    vector<int> id(N);
    iota(all(id),0);

    int ans = 0;
    do {    

        int cnt = 0;
        for (int i=0; i<N; i+=2) {
            if (A[id[i]]*2 <= A[id[i+1]]) cnt++;
        }
        ans = max(ans,cnt);

    } while (next_permutation(all(id)));

    cout << ans << endl;

    return 0;
}
