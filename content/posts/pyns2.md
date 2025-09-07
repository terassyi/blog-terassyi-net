+++
categories = [ "tech" ]
tags = [ "network", "namespace", "ebpf", "python", "sechack365", "oss" ]
date = 2020-12-21
title = "Linux Network Namespaceを使用したネットワークシミュレータの紹介"
description = "Linux Network Namespaceを使用してyamlファイルから仮想ネットワークを自由に作ることのできるツールを作っています．"
+++

こんにちは．12月に入り非常に寒い日々が続いています．個人的には10月から続いていたセキュリティキャンプが一段落して少し余裕が出てきました．
また，この記事は[SecHack365 Advent Calendar 2020](https://adventar.org/calendars/5335)の記事として書いています．
今回は趣味で開発しているツールを紹介します．

<!--more-->

# pyns2の紹介
pyns2という名前で開発しています．python + network simulator + network namespaceで名付けました．

リポジトリはこちら

{{<github repo="terassyi/pyns2">}}


このツールはLinuxの標準機能として提供されているNamespaceの一つである`Network Namespace`を使用して一つのホスト内で仮想的にデバイスなどを分離して仮想ネットワークを作成するためのツールです．

`Network Namespace`を使用して仮想ネットワークを作成することで軽量かつ柔軟にネットワークを作ることができます．また，実際のソフトウェアやツールをその仮想ネットワーク上で動作させることができるのでイメージがつきやすいです．複数のコンテナでネットワークを作るのと比較してもイメージを用意しなくていいので簡単に動作させることができるようになっています．

## モチベーション
動機はネットワークの実験をする際に一つのホスト上で仮想ネットワークを作って実験することが多いのですが，毎回同一のネットワーク環境を構築するのが手間だったり設定覚えられなかったりするのでIaC的に管理できるといいなと思ったことです．

## Linux Network Namespace
Linuxにはnamespaceという機能があり，これらの名前空間を分離することでプロセスがあたかも独立したリソースを持っているように振舞うことができるようになります．コンテナ仮想化はこの名前空間分離機能を用いて実現されています．詳しくは[namespaceのman](https://linuxjm.osdn.jp/html/LDP_man-pages/man7/namespaces.7.html)を参照してください．
Network Namespaceはその中の一つでネットワーク関連のシステムリソースの分離を実現します．
簡単にNetwork Namespaceの機能を使用するには`ip netns`コマンドを使用します．
詳しい使い方はこちら([ip netnsコマンドの使い方（ネットワークの実験の幅が広がるなぁ～）](https://qiita.com/hana_shin/items/ab078b5552f5df029030))を参照してください．

## ip netnsとpyns2
`pyns2`で構築することのできる仮想ネットワークは`ip netns`コマンド(一部`iptables`)で実現することができます．
シェルスクリプトを用意してあげるのももちろんありですがyamlで定義できる方が宣言的にリソースを定義できますし，削除など管理が楽になります．また，複雑なネットワークを構築することも簡単になります．

## 動作環境
`pyns2`はLinux環境でのみ動作します．
リポジトリに`Vagrantfile`と`Dockerfile`, `docker-compose.yml`を用意しているのでそちらを使用してください．

コンテナ環境上ではNATを使用した外部ネットワークへのアクセスは使用できませんがインターネットにアクセスできる仮想ネットワークを作成しない限りはDocker上での動作で十分だと思います．

詳しい使い方は[README.md](https://github.com/terassyi/pyns2/blob/master/README.md)に記載しています．

## 使ってみる
今回はVagrantを使用してVM上で仮想ネットワークを作成してみます．
VagrantでVMを起動してVMに接続します．
```shell
$ git clone https://github.com/terrasyi/pyns2
$ cd pyns2
$ vagrant up
$ vagrant ssh
# enter vm
$ sudo su
$ cd pyns2
```

### 定義ファイル
`examples/`配下にある`example-container.yml`を起動してみます．中身は以下のようになっています．
こちらの例は複数のコンテナが起動しているDockerネットワークを再現しています．
二台の仮想ホストとホスト上にブリッジデバイスが定義されていてブリッジを経由して各仮想ホストは疎通ができます．また，NATの設定が定義されているためホスト上のNAT(iptables)を経由してインターネットに接続することができます．
```yaml
example-network-container:
    host:
        ifaces:
            br0:
                type: "bridge"
                address: "192.168.50.2/24"
                ifaces:
                    - "host1-veth1-br"
                    - "host2-veth1-br"
                    - "host-veth1-br"
            host-veth1:
                type: "veth"
                address: "192.168.50.1/24"
                peer: "host-veth1-br"
        nat:
          src: "192.168.50.0/24"
          out_iface: "eth0"

    netns:
        host1:
            ifaces:
                host1-veth1:
                    type: "veth"
                    address: "192.168.50.100/24"
                    peer: "host1-veth1-br"
            routes:
              - route:
                    gateway: "192.168.50.1"
                    dest: "default"

        host2:
            ifaces:
                host2-veth1:
                    type: "veth"
                    address: "192.168.50.101/24"
                    peer: "host2-veth1-br"
            routes:
                - route:
                    gateway: "192.168.50.1"
                    dest: "default"
```

### 仮想ネットワークの作成
実際に実行して仮想ネットワークを作成してみます．
作成には`run`コマンドを使用します．
```
root@ubuntu2004:/home/vagrant# pyns2 run pyns2/examples/example-container.yml
[info] Created Network Namespace host1
[info] register netns id host1
[info] Created Network Namespace host2
[info] register netns id host2
[info] create bridge interface name=br0
[info] create veth interface name=host-veth1
[info] create veth interface name=host1-veth1
[info] create veth interface name=host2-veth1
[info] create NAT setting
[info] host1-veth1 is set netns=host1
[info] host2-veth1 is set netns=host2
[info] set address=192.168.50.2/24 to br0
[info] set address=192.168.50.1/24 to host-veth1
[info] set address=192.168.50.100/24 to host1-veth1
[info] set address=192.168.50.101/24 to host2-veth1
[info] Network Interface(host-veth1) is Up
[info] Network Interface(host1-veth1) is Up
[info] Network Interface(host2-veth1) is Up
[info] dest=default gateway=192.168.50.1 in ns=host1
[info] dest=default gateway=192.168.50.1 in ns=host2
root@ubuntu2004:/home/vagrant#
```

### 疎通確認
作成した各ホストの疎通を確認してみます．

#### host(192.168.50.1) -> host1(192.168.50.100)
```
root@ubuntu2004:/home/vagrant# ping 192.168.50.100 -c 3
PING 192.168.50.100 (192.168.50.100) 56(84) bytes of data.
64 bytes from 192.168.50.100: icmp_seq=1 ttl=64 time=0.071 ms
64 bytes from 192.168.50.100: icmp_seq=2 ttl=64 time=0.055 ms
64 bytes from 192.168.50.100: icmp_seq=3 ttl=64 time=0.053 ms

--- 192.168.50.100 ping statistics ---
3 packets transmitted, 3 received, 0% packet loss, time 2048ms
rtt min/avg/max/mdev = 0.053/0.059/0.071/0.008 ms
```
無事に疎通が取れています．

#### host(192.168.50.1) -> host2(192.168.50.101)
```
root@ubuntu2004:/home/vagrant# ping 192.168.50.101 -c 3
PING 192.168.50.101 (192.168.50.101) 56(84) bytes of data.
64 bytes from 192.168.50.101: icmp_seq=1 ttl=64 time=0.093 ms
64 bytes from 192.168.50.101: icmp_seq=2 ttl=64 time=0.136 ms
64 bytes from 192.168.50.101: icmp_seq=3 ttl=64 time=0.067 ms

--- 192.168.50.101 ping statistics ---
3 packets transmitted, 3 received, 0% packet loss, time 2034ms
rtt min/avg/max/mdev = 0.067/0.098/0.136/0.028 ms
```
こちらも疎通できているようです．

#### host1(192.168.50.100) <-> host2(192.168.50.101)
```
root@ubuntu2004:/home/vagrant# pyns2 exec host1
root@ubuntu2004:/home/vagrant# ping 192.168.50.101 -c 3
PING 192.168.50.101 (192.168.50.101) 56(84) bytes of data.
64 bytes from 192.168.50.101: icmp_seq=1 ttl=64 time=0.048 ms
64 bytes from 192.168.50.101: icmp_seq=2 ttl=64 time=0.045 ms
64 bytes from 192.168.50.101: icmp_seq=3 ttl=64 time=0.038 ms

--- 192.168.50.101 ping statistics ---
3 packets transmitted, 3 received, 0% packet loss, time 2035ms
rtt min/avg/max/mdev = 0.038/0.043/0.048/0.004 ms
root@ubuntu2004:/home/vagrant# exit
root@ubuntu2004:/home/vagrant# ping 192.168.50.100 -c 3
PING 192.168.50.100 (192.168.50.100) 56(84) bytes of data.
64 bytes from 192.168.50.100: icmp_seq=1 ttl=64 time=0.038 ms
64 bytes from 192.168.50.100: icmp_seq=2 ttl=64 time=0.047 ms
64 bytes from 192.168.50.100: icmp_seq=3 ttl=64 time=0.043 ms

--- 192.168.50.100 ping statistics ---
3 packets transmitted, 3 received, 0% packet loss, time 2040ms
rtt min/avg/max/mdev = 0.038/0.042/0.047/0.003 ms
```
`pyns2 exec`コマンドで`host1`, `host2`の名前空間に入り`ping`を飛ばしてみるとこちらも疎通が取れています．

#### host1(192.168.50.100) -> internet(8.8.8.8)
最後にインターネットと仮想ホストとの疎通を確認します．
```
root@ubuntu2004:/home/vagrant# pyns2 exec host1
root@ubuntu2004:/home/vagrant# pyns2 check_netns
host1
root@ubuntu2004:/home/vagrant# ping 8.8.8.8 -c 3
PING 8.8.8.8 (8.8.8.8) 56(84) bytes of data.
64 bytes from 8.8.8.8: icmp_seq=1 ttl=61 time=18.5 ms
64 bytes from 8.8.8.8: icmp_seq=2 ttl=61 time=19.4 ms
64 bytes from 8.8.8.8: icmp_seq=3 ttl=61 time=17.3 ms

--- 8.8.8.8 ping statistics ---
3 packets transmitted, 3 received, 0% packet loss, time 2004ms
rtt min/avg/max/mdev = 17.332/18.391/19.374/0.835 ms
```
無事インターネットと疎通できています．


#### 仮想ネットワークの削除
実験が終わったら作成したネットワークを削除します．
削除には`pyns2 delete`コマンドを使用します．
```
root@ubuntu2004:/home/vagrant# pyns2 delete pyns2/examples/example-container.yml
[INFO] Delete interface br0 in host namespace
[INFO] Delete interface host-veth1 in host namespace
[info] delete NAT setting
[INFO] Delete netns host1
[INFO] Delete netns host2
```
これで無事に削除されました．

`examples/`配下にいくつかネットワークの例を作成しているので是非試してみてください．

## まとめ
今回は趣味で開発しているネットワークシミュレーションツールを紹介しました．
作成したネットワーク上でLinuxコマンドを使用できるのでネットワークの学習にも役に立つのではないかなと思います．
簡単に使えるように`Vagrantfile`や`Dockerfile`を用意しているので是非遊んでみてください．
今後はまだ未実装のインターフェースタイプへの対応やネットワークプロトコルのシミュレーションに対応していきたいと考えています．
バグ報告(たくさんある)や面白いネットワーク例の追加などあれば是非お知らせください．
