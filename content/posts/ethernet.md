+++
categories = [ "tech" ]
tags = [ "network", "golang", "ethernet" ]
date = 2020-03-29
title = "ネットワークを作って理解しようとする(Ethernet編)"
description = "本記事はネットワークを作って理解しようとするシリーズのEthernet編です．生のデータをNICから取ってきてEthernetのフォーマットに加工するまでを記します."
+++

こんにちは．
今週末は新型コロナの影響で外出自粛なので暇を持て余しております．
暇なのでNetflixで鬼滅の刃を見始めました．面白いですね〜．

## ネットワークを作って理解する
最近の興味としてネットワークの仕組みを理解したいというのがあり，プロトコルスタック自作なるものを知りました．とはいえ僕はC言語が得意でないのでGo言語で作ってみようと思い作成を始めました．というわけて何回かに分けて紹介したいと思います．

## OSI参照モデル
OSI参照モデルとはコンピュータの通信機能を階層構造に分割したモデルです．
各階層にはそれぞれが担うべき機能が定義されています．
データリンク層では隣接するノード間のデータの通信をサポートします．
![osi-model](/img/osi-model.png)

## 開発環境
開発環境は以下の通りです．```ioctl```などのシステムコールを扱うためprivilegeオプションを有効にしたLinuxコンテナを作成してプログラムをビルドします．
また，実行はコンテナの中でネットワーク名前空間を分離して行います．
- Mac OS Catalina
- VSCode
- Docker version 19.03.5, build 633a0ea

## 実装
リポジトリは[こちら](https://github.com/terassyi/proto)

### 物理層からデータを受け取る
今回のプログラムでは生のパケットを受け取る必要があります．golangの標準パッケージでは生のパケットを扱うことができないため別の方法で生のパケットを取得しなければいけません．そこで今回のプログラムでは以下の二つの方法で生のパケットを取得します．
- PF_PACKET
- Tun/Tapデバイス

#### PF_PACKET
PF_PACKETはLinuxのsocketシステムコールで生のパケットを扱うためのドメインです．syscallパッケージのSocket関数を用いて以下のようにソケットを開きます．
```go
protocol := hton16(syscall.ETH_P_ALL)
fd, err := syscall.Socket(syscall.AF_PACKET, syscall.SOCK_RAW, int(protocol))
if err != nil {
    return -1, err
}
```
開いたソケットを用いてPFPacket構造体を定義します．
```go
type PFPacket struct {
	fd                 int
	name               string
	address            ethernet.HardwareAddress
	netInfo            ip.IPSubnetMask
	registeredProtocol []LinkNetProtocol
	MTU                int
	buffer             chan *ethernet.EthernetFrame
}
```
#### Tun/Tap
Tun/TapはUnixで使用できる仮想ネットワークデバイスです．Tun/Tapデバイスに届いたパケットは直接ユーザープログラムに送られます．
Tun/Tapデバイスは以下のように開きます．
```go
const device = "/dev/net/tun"

file, err := os.OpenFile(device, os.O_RDWR, 0600)
	if err != nil {
		return "", nil, err
	}
```
開いたファイルを用いてTun構造体を定義します．
```go
type Tun struct {
	file               io.ReadWriteCloser
	name               string
	address            ethernet.HardwareAddress
	netInfo            ip.IPSubnetMask
	registeredProtocol []LinkNetProtocol
	MTU                int
	buffer             chan *ethernet.EthernetFrame
}
```

#### Deviceインターフェース
DeviceインターフェースでPF_PACKETとTunデバイスの差を吸収します．
```go
type Device interface {
	Read(data []byte) (int, error)
	Write(data []byte) (int, error)
	Close() error
	Address() ethernet.HardwareAddress
	Name() string
	NetInfo() ip.IPSubnetMask
	IPAddress() ip.IPAddress
	Subnet() ip.IPAddress
	Netmask() ip.IPAddress
	RegisterNetInfo(info string) error
	RegisterProtocol(protocol LinkNetProtocol) error
	RegisteredProtocol() []LinkNetProtocol
	DeviceInfo()
	Handle()
	Next()
	Buffer() chan *ethernet.EthernetFrame
}
```
先ほどのPFPacket, Tun型にDeviceインターフェースを満たすためのメソッドを全て実装することでPFPacket, Tun型はDevice型として振舞うことができ，インターフェースの違いを吸収できます．

### パケットをEthernetのフォーマットに整形する
Ethernetフレームにデータを整形します．
```go
type HardwareAddress [6]byte

type EtherType uint16

type EthernetHeader struct {
	Dst  HardwareAddress
	Src  HardwareAddress
	Type EtherType
}

type EthernetFrame struct {
	Header EthernetHeader
	Data   []byte
}
```
ネットワークインターフェースから取得したバイト列をbytesパッケージを用いていい感じにEthernetFrame型にパースします．
```go
func NewEthernet(data []byte) (*EthernetFrame, error) {
	frame := &EthernetFrame{}
	header := &EthernetHeader{}
	buf := bytes.NewBuffer(data)
	if err := binary.Read(buf, binary.BigEndian, header); err != nil {
		return nil, err
	}
	frame.Header = *header
	frame.Data = buf.Bytes()
	return frame, nil
}
```
とりあえずこれで生のデータをEthernetフレームとして扱うことができるようになりました．
Ethernetはデータのフォーマット以外に大した処理を行わないので簡単です．
Ethernetフレームをバイト列に変換するためにパースと同様にbytesパッケージのWrite()関数を用います．

### 上位層のプロトコルへデータを受け渡す
Ethernetを扱うことができるようになったので上位層のプロトコル(IPとARP)にデータを渡すことができるようにします．

#### どのように上位層にデータを伝搬するか
Device型を実装しているPFPacket, Tun型のフィールドである```registeredProtocol []LinkNetProtocol```に上位層のプロトコルを登録することで上位層のメソッドを呼び出せるようにします．
登録する上位層プロトコルの各型は```LinkNetProtocol```インターフェースを満たす必要があります．
Device型のメソッドである
```go
RegisterProtocol(protocol LinkNetProtocol) error
```
を用いてregisteredProtocolフィールドに登録します．
また，HandleメソッドとNextメソッドを用いて上位層へのデータの伝搬を実現します．
以下がHandleメソッドとNextメソッドの実装です．
```go
func (p *PFPacket) Handle() {
	buffer := make([]byte, p.MTU)
	// fmt.Printf("%v start handling packet", p.name)
	fmt.Println("packet handling start")
	for {
		_, err := p.Read(buffer)
		if err != nil {
			log.Printf("%v error (read): %v\n", p.name, err)
		}
		frame, err := ethernet.NewEthernet(buffer)
		if err != nil {
			log.Printf("%v error (read): %v\n", p.name, err)
		}
		p.buffer <- frame
	}
}
```
Handleメソッドではデバイスからデータを受け取りEthernetフレームに整形してbufferフィールド(channel)にデータを渡します．
```go
func (p *PFPacket) Next() {
	for {
		if p.registeredProtocol == nil {
			panic("next layer protocol is not registered")
		}
		// frame := <-p.buffer
		frame := <-p.Buffer()
		for _, protocol := range p.registeredProtocol {
			if protocol.Type() == frame.Header.Type {
				err := protocol.Handle(frame.Payload())
				if err != nil {
					log.Printf("%v error: %v\n", p.name, err)
				}
			}
		}
	}
}
```
Nextメソッドはbufferを取り出してregisterdProtocolフィールドに格納されている上位プロトコルと一致した場合そのプロトコルのHandleメソッドを呼び出します．

これによりデータを上位層に伝搬させることができます．

## 実験
テストとしてEthernetフレームを読むだけのテストコードを実行して実際にパケットが受信できているか確認することができます．
```go
func TestRead(t *testing.T) {
	dev, err := NewDevicePFPacket("client_veth0", 1500)
	if err != nil {
		t.Fatal(err)
	}
	dev.DeviceInfo()
	defer dev.Close()
	buffer := make([]byte, 1500)
	for {
		_, err := dev.Read(buffer)
		if err != nil {
			t.Fatal(err)
		}
		eth, err := ethernet.NewEthernet(buffer)
		if err != nil {
			t.Fatal(err)
		}
		eth.Header.PrintEthernetHeader()
	}
}
```

## まとめ
今回はEthernetを作ってみました．Ethernetプロトコル自体はパケットのフォーマット以外にやることはないので簡単でした．上位層のプロトコルにどのようにデータを伝搬するかが問題です．プログラムを作成するために以下の資料を参考にさせていただきました．ありがとうございます．

次回はARP編を書きたいです．

### 参考
- [https://github.com/pandax381/microps](https://github.com/pandax381/microps)
- [https://github.com/pandax381/lectcp](https://github.com/pandax381/lectcp)
- [ルーター自作でわかるパケットの流れ](https://www.amazon.co.jp/gp/product/4774147451/ref=ppx_yo_dt_b_asin_title_o03_s00?ie=UTF8&psc=1)
