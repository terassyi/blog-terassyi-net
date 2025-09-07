+++
categories = [ "tech" ]
tags = [ "network", "golang", "arp" ]
date = 2020-04-01
title = "ネットワークを作って理解しようとする(ARP編)"
description = "本記事はネットワークを作って理解しようとするシリーズのARP編です．RFCを参考にしながらARPを実装してみます．"
+++

こんにちは．
新型コロナの影響で外出を控えているのですが，ずっと自宅にいるのも結構しんどいですね．
この前見始めた鬼滅の刃ももう見終わってしまいました．続きが気になります．
さて，今回もネットワークシリーズです．

## ネットワークを作って理解する

ネットワークの仕組みを理解するためには作ってみるのが一番ということでプロトコルスタックを自作してみます．
前回はEthernetを実装してみました．[前回のポストはこちら](https://terassyi.net/posts/2020/03/29/ethernet.html)
今回はデータリンク層のアドレスとネットワーク層のアドレスを解決するARPを実装してみたいと思います．使用言語はgolangです．

<!--more-->

## 開発環境

開発環境は前回と同様で以下の通りです．```ioctl```などのシステムコールを扱うためprivilegeオプションを有効にしたLinuxコンテナを作成してプログラムをビルドします．
また，実行はコンテナの中でネットワーク名前空間を分離して行います．

- Mac OS Catalina
- VSCode
- Docker version 19.03.5, build 633a0e

## 仕様とRFC826 ARP

ARPの仕様は[RFC826](http://srgia.com/docs/rfc826j.html)に定義されています．
ARPの役割はデータリンク層の物理アドレスとネットワーク層のアドレスt(IPアドレスなど)を解決することです．詳細はRFCを読んでみてください．

ARPは```request```と```reply```の二つのオペレーションから構成されています．
各端末がrequestとreplyを送受信することで物理アドレスと論理アドレスを対応づけます．
ARPでの通信が行われる際は当然まだ論理アドレスでの通信はできないため物理アドレスを用いて通信を行います．
パケットフォーマットは以下の通りです．
![arp-format](/img/arp-format.png)

### 動作

各端末はARPパケットを受信したらまず受信パケットの以下のフィールドを調べます．

- ハードウェアタイプ
- ハードウェアアドレス長
- プロトコルアドレス長
次に調査したアドレスが自身の変換テーブルに登録されいるかを調べます．
既に登録されている場合，テーブルの内容を更新します．
登録されていない場合テーブルに新しく情報を追加します．
次に，パケットのオペレーションコードを調べてRequestの場合は自分の物理アドレスと論理アドレスをパケットにセットしてReplyパケットを作成して返信します．

#### ARP Request

Requestは通信を行いたい相手の物理アドレスを知りたい時にネットワーク内にブロードキャストされます．
![arp-request](/img/arprequest.png)

#### ARP Relpy

Replyは受信したRequestに応答するために送信されます．
Requestパケットにセットされていた論理アドレスを持つホストによってRequestを送信したホストに向けて送信されます．Replyパケットには自身の物理アドレスがセットされます．
![arpreply](/img/arpreply.png)

これにより各端末は同じネットワーク内の各端末の物理アドレスと論理アドレスを対応づけることができるようになります．


## 実装

リポジトリは[こちら](https://github.com/terassyi/proto)

というわけで実際に作ってみます．

### ARPパケットフォーマット

ARPパケットのフォーマット構造体です．
```ARPPacket```構造体のHardware AddressとProtocol Addressフィールドはネットワーク内で使用されるプロトコルによってアドレス長が変化するので```[]byte```を使用します．
ほとんどの場合がMAC AddressとIPv4アドレスですが，Ipv6アドレスの可能性も考えられます．(今回の実装ではEthernetとIPv4のみですが)

```go
type ARPHeader struct {
	HardwareType HardwareType
	ProtocolType ProtocolType
	HardwareSize uint8
	ProtocolSize uint8
	OpCode       OperationCode
}

type ARPPacket struct {
	Header                ARPHeader
	SourceHardwareAddress []byte
	SourceProtocolAddress []byte
	TargetHardwareAddress []byte
	TargetProtocolAddress []byte
}

type HardwareType uint16
type ProtocolType uint16
type OperationCode uint16
```

#### パケットのパース

```bytes```パッケージを使用してパケットをパース・シリアライズします．
先にヘッダをパースしてアドレス長を取得することでパケットの各フィールドを長さを指定してスライスを初期化して，その後各フィールドをReadします．

```go
arpPacket := &ARPPacket{
		Header:                *arpHeader,
		SourceHardwareAddress: make([]byte, arpHeader.HardwareSize),
		SourceProtocolAddress: make([]byte, arpHeader.ProtocolSize),
		TargetHardwareAddress: make([]byte, arpHeader.HardwareSize),
		TargetProtocolAddress: make([]byte, arpHeader.ProtocolSize),
    }
if err := binary.Read(buf, binary.BigEndian, arpPacket.SourceHardwareAddress); err != nil {
		return nil, err
	}
```
シリアライズする際は特に気にすることなく```bytes.Write()```します．便利．

### パケットを生成する

ARPではRequestとReplyの二つのタイプがあるのでRequest関数とReply関数を用意します．

```go
func Request(srcHardwareAddress, srcProtocolAddress, targetProtocolAddress []byte, protocolType ProtocolType) (*ARPPacket, error) {
	var protocolSize uint8
	switch protocolType {
	case PROTOCOL_IPv4:
		protocolSize = uint8(4)
	case PROTOCOL_IPv6:
		protocolSize = uint8(16)
	default:
		return nil, fmt.Errorf("invalid protocol")
	}
	header := ARPHeader{
		HardwareType: HARDWARE_ETHERNET,
		ProtocolType: protocolType,
		HardwareSize: uint8(6),
		ProtocolSize: protocolSize,
		OpCode:       ARP_REQUEST,
	}
	return &ARPPacket{
		Header:                header,
		SourceHardwareAddress: srcHardwareAddress,
		SourceProtocolAddress: srcProtocolAddress,
		TargetHardwareAddress: ethernet.BroadcastAddress[:],
		TargetProtocolAddress: targetProtocolAddress,
	}, nil
}
```

```go
func Reply(srcHardwareAddress, srcProtocolAddress, targetHardwareAddress, targetProtocolAddress []byte, protocolType ProtocolType) (*ARPPacket, error) {
	var protocolSize uint8
	switch protocolType {
	case PROTOCOL_IPv4:
		protocolSize = uint8(4)
	case PROTOCOL_IPv6:
		protocolSize = uint8(16)
	default:
		return nil, fmt.Errorf("invalid protocol")
	}
	header := ARPHeader{
		HardwareType: HARDWARE_ETHERNET,
		ProtocolType: protocolType,
		HardwareSize: uint8(6),
		ProtocolSize: protocolSize,
		OpCode:       ARP_REPLY,
	}
	return &ARPPacket{
		Header:                header,
		SourceHardwareAddress: srcHardwareAddress,
		SourceProtocolAddress: srcProtocolAddress,
		TargetHardwareAddress: targetHardwareAddress,
		TargetProtocolAddress: targetProtocolAddress,
	}, nil
}
```

### ARPテーブル

ARPテーブルに各ホストの論理アドレスと物理アドレスのペアを保存する構造体です．
```Entry```構造体に物理アドレスと論理アドレスのペアを格納し，```ARPTable```構造体のEntrys(複数形間違ってますね笑)フィールドに格納されます．
また，ARPTableは複数のgoroutineから参照されるため```sync.Mutex```をフィールドに持たせています．

```go
type Entry struct {
	HardwareAddress []byte
	ProtocolAddress []byte
	ProtocolType    ProtocolType
	TimeStamp       time.Time
}

type ARPTable struct {
	Entrys []*Entry
	Mutex  sync.RWMutex
}
```

テーブル操作の一例として```Upate```メソッドを示します．他のメソッドも同様にEntrysフィールドから目的のものを走査しています．```Mutex.Lock```,```Mutex.Unlock```をしっかりしましょう．

```go
func (at *ARPTable) Update(hwaddr, protoaddr []byte) (bool, error) {
	at.Mutex.Lock()
	defer at.Mutex.Unlock()
	for _, e := range at.Entrys {
		if bytes.Equal(e.ProtocolAddress, protoaddr) {
			e.HardwareAddress = hwaddr
			e.TimeStamp = time.Now()
			return true, nil
		}
	}
	return false, nil
}
```

### ARPパケットを処理する

パケット，テーブルの用意ができたのでARPプロトコルを処理するパートを実装します．
まずはARP型を定義します．
フィールドにはARPテーブルと```Device```型を持ちます．これはARPがデータリンク層で通信を行うためです．

```go
type ARP struct {
	HardwareType ethernet.EtherType
	Table        *arp.ARPTable
	Dev          Device
}
```

```ARP```型は```LinkNetProtocol```インターフェースを満たすため```LinkNetProtocol```型として振舞うことができます．そのため，[前回の記事](http://localhost:8080/posts/2020/03/29/ethernet.html#%E4%B8%8A%E4%BD%8D%E5%B1%A4%E3%81%AE%E3%83%97%E3%83%AD%E3%83%88%E3%82%B3%E3%83%AB%E3%81%B8%E3%83%87%E3%83%BC%E3%82%BF%E3%82%92%E5%8F%97%E3%81%91%E6%B8%A1%E3%81%99)で紹介した```Device```型を満たす型の```registeredProtocol```フィールドに登録することができます．```LinkNetProtocol```インターフェースは以下のように定義されています．

```go
type LinkNetProtocol interface {
	Type() ethernet.EtherType
	Handle(data []byte) error
	Write(dst []byte, protocol interface{}, data []byte) (int, error)
}
```

```Handle```メソッドがARPの具体的な処理を担います．
[動作](#動作)に記述したような処理ですね．

```go
func (a *ARP) Handle(data []byte) error {
	packet, err := arp.NewARPPacket(data)
	if err != nil {
		return fmt.Errorf("failed to create ARP packet")
	}
	if packet.Header.HardwareType != arp.HARDWARE_ETHERNET {
		return fmt.Errorf("invalid hardware type")
	}
	if packet.Header.ProtocolType != arp.PROTOCOL_IPv4 && packet.Header.ProtocolType != arp.PROTOCOL_IPv6 {
		return fmt.Errorf("invalid protocol type")
	}
	mergeFlag, err := a.Table.Update(packet.SourceHardwareAddress, packet.SourceProtocolAddress)
	if err != nil {
		return err
	}
	if bytes.Equal(packet.TargetProtocolAddress, a.Dev.IPAddress().Bytes()) {
		if !mergeFlag {
			err := a.Table.Insert(packet.SourceHardwareAddress, packet.SourceProtocolAddress, packet.Header.ProtocolType)
			if err != nil {
				return fmt.Errorf("Failed to insert: %v", err)
			}
		}
		if packet.Header.OpCode == arp.ARP_REQUEST {
			err := a.ARPReply(packet.SourceHardwareAddress, packet.SourceProtocolAddress, packet.Header.ProtocolType)
			if err != nil {
				return err
			}
		}
	}
	return nil
}
```

## 実験

一通りの処理を実装し終えたので実際に実行して実験を行います．
実行にはDockerを使用します．

### 準備

実験するネットワーク環境と実験コードを用意します．

#### 実験ネットワーク環境

docker-compose.yamlを用意しているのでコンテナを起動した後コンテナに入って```./script/arp-setup.sh```を実行します．ファイルの中身は以下です．

```sh
#! /bin/bash

#
#  -------                                   -------
#  |host1|host1_veth0 <---------> host2_veth0|host2|
#  ------- 192.168.0.2/24     192.168.0.3/24 -------
#

ip netns add host1
ip netns add host2

ip link add host1_veth0 type veth peer host2_veth0

ip link set host1_veth0 netns host1
ip link set host2_veth0 netns host2

ip netns exec host1 ip addr add 192.168.0.2/24 dev host1_veth0
ip netns exec host2 ip addr add 192.168.0.3/24 dev host2_veth0

ip netns exec host1 ip link set lo up
ip netns exec host2 ip link set lo up
ip netns exec host1 ip link set host1_veth0 up
ip netns exec host2 ip link set host2_veth0 up
```

```ip netns```コマンドでネットワーク名前空間を分けています．
```ip netns```を使用することで柔軟なネットワーク実験が行えます．すごい便利です．
というわけで実験の準備が整いました．

#### 実験コード

実験コードはこちら.

```go
func TestARPHandler(t *testing.T) {
	dev, err := NewDevicePFPacket("host1_veth0", 1500)
	if err != nil {
		t.Fatal(err)
	}
	dev.RegisterNetInfo("192.168.0.2/24")
	arp := NewARP(dev)
	err = dev.RegisterProtocol(arp)
	if err != nil {
		t.Fatal(err)
	}
	dev.DeviceInfo()
	defer dev.Close()
	go dev.Handle()
	dev.Next()
}
```

### 実行

今回はhost1で作成したプログラムを実行します．
次のコマンドを実行します．

```
ip netns exec host1 go test -run TestARPHandle
```

すると，こんな感じで表示されます．

```
[root@13eca954d7e7 net]# ip netns exec host1 go test -run TestARPHandle
----------device info----------
name:  host1_veth0
fd =  3
hardware address =  aa:5d:24:9d:c7:d2
packet handling start
<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
---------------arp---------------
hardware type = 01
protocol type = 800
hardware address size = 06
protocol address size = 04
operation code = (REQUEST)
src hwaddr = 7e:37:27:b1:cc:91
src protoaddr = 192.168.0.3
target hwaddr = 00:00:00:00:00:00
target protoaddr = 192.168.0.2
[info]reply send >>
---------------arp table---------------
hwaddr= 7e:37:27:b1:cc:91
protoaddr=192.168.0.3
time=2020-04-01 12:27:51.7183355 +0000 UTC m=+9.093416001
---------------------------------------
<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
---------------arp---------------
hardware type = 01
protocol type = 800
hardware address size = 06
protocol address size = 04
operation code = (REPLY)
src hwaddr = aa:5d:24:9d:c7:d2
src protoaddr = 192.168.0.2
target hwaddr = 7e:37:27:b1:cc:91
target protoaddr = 192.168.0.3
```

192.168.0.3(host2)からARPリクエストが飛んできていることがわかります．
また，パケットの内容をARPテーブルに保存して，リプライパケットを送信しているのがわかります．
いい感じに動作しているようです．

## まとめ

今回は前回のEthernetに引き続きARPを実装してみました．
ARPがMACアドレスとIPアドレスを解決するためのプロトコルであることは理解していましたが，実際に実装してみることで詳しい処理の内容やパケットの詳しい構成を理解することができて勉強になりました．
また，RFCを読みながら実装するのも勉強になりますね．
次回はIPv4編を書きたいです．
新型コロナ早く終息して欲しいですね．

### 参考

- [https://github.com/pandax381/microps](https://github.com/pandax381/microps)
- [https://github.com/pandax381/lectcp](https://github.com/pandax381/lectcp)
- [ルーター自作でわかるパケットの流れ](https://www.amazon.co.jp/gp/product/4774147451/ref=ppx_yo_dt_b_asin_title_o03_s00?ie=UTF8&psc=1)
