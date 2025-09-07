+++
categories = [ "tech" ]
tags = [ "network", "rust", "dhcp" ]
date = 2020-03-24
title = "ネットワークを作って理解しようとする(DHCP編)"
description = "本記事ではDHCPプロトコルを簡単なDHCPサーバーを実装することで理解してみます．"
+++

今回はDHCPプロトコルをサーバーを実装することで理解してみます．使用する言語はRustです．普段はGoを書いていますが，新しい言語としてRustの勉強を始めたため学習のため選択しました．Rustは[プログラミング言語Rust](https://doc.rust-jp.rs/book/second-edition/)を一通り読んだだけで実際にプログラムを書いたことはほどんどありません．なので読みにくいです．ちなみにモチベ維持のため作りながら書いてます．
- リポジトリ [rusdhcp](https://github.com/terassyi/rusdhcp)

{{<github repo="terassyi/rusdhcp">}}

<!--more-->

プログラムを作成するにあたり[Rustで始めるネットワークプログラミング](https://www.amazon.co.jp/gp/product/B07SW2GXVF/ref=ppx_yo_dt_b_d_asin_title_o00?ie=UTF8&psc=1)を大変参考にさせていただきました．ありがとうございます．

## RFC2131 Dynamic Host Configuration Protocol
DHPCの仕様は[RFC2131](http://srgia.com/docs/rfc2131j.html)で定義されています．思っていたより複雑でした．

## RFC1533 DHCP Options and BOOTP Vendor Extensions
DHCPのパケットには可変長のオプションが定義されており，オプションフィールドの仕様は[RFC1533](https://tools.ietf.org/html/rfc1533)に記載されています．

## 仕様
あくまで学習用として作成するので完全なものでなく，ある程度の機能を持ったDHCPサーバーにしたいと思います．(時間とモチベと能力があればちゃんとしたい)

### 機能
RFC1533に定義されているオプションのすべてを実装するのはしんどいので機能をしぼっていくつかのオプションタイプのみをサポートします.サポートするオプションタイプは以下です．また，リレーエージェントについても機能を省きます．実装が複雑になる上，実験環境の構築もめんどくさいためです．
- DHCPDISCOVER
- DHCPOFFER
- DHCPREQUEST
- DHCPACK
- DHCPNAK
- DHCPRELEAS

ネットワークアドレスの動的な割り当てやアドレスの管理がDHCPサーバーの主な役割です．

#### アドレスの割り当て
DHCPサーバーが起動しているネットワークにクライアントが参加すると，クライアントはDHCPDISCOVERメッセージをネットワークにブロードキャストします．それを受け取ったサーバーはクライアントからの要求に応じリースするアドレスを決定してそのアドレスとともにDHCPOFFERメッセージを返信(ブロードキャスト)します．クライアントはDHCPREQUESTメッセージでオファーされたアドレスを使用するかを返信します．使用する場合はデータベースにクライアントの情報を保存します．その後，DHCPACKを返信して割り当てが完了します．

#### アドレスの確認とリースの延長
クライアントにリースされているアドレスの確認とリース期間の延長はDHCPREQUESTがクライアントから送られることで行われます．サーバーはクライアントから提示された情報が正しい場合DHCPACKを応答してそれ以外ではDHCPNAKを応答します．

#### アドレスの解放
リースされているアドレスを解放するために，DHCPRELEASがクライアントから送信されます．メッセージを受信したサーバーはバインドしているアドレスを解放します．その際クライアントの情報はできるだけ保持されなければなりません．(今回は設計のミスなどもあり単に情報を捨てます．)

### 開発環境
開発環境は以下の通りです．コードはMac上で編集しビルドはDockerにたてたLinux(Debian)で行います．~~実行はコンテナ内でip netnsを使用してネットワーク名前空間を分けて動作させます．~~と考えてましたが名前空間を分離した環境ではbroadcastをする際にNetwork is unreachableになってしまうためやむなく家のルーターのDHCP機能を無効にしてMac上で実行しました．
- Mac OS Catalina
- VSCode
- Cargo 1.42.0
- ~~Docker version 19.03.5~~
- ~~rust:latest image~~

## 実装
### DHPCパケットフォーマット
まずはDHCPのパケットフォーマットに合わせて構造体を定義します．パターンが決まっているフィールドについては出来るだけenumで定義します．Rustにはenumがあるのはいいですね．match式好きなので嬉しいです．UDPのペイロードからバイト列として取り出して頑張ってパケットフォーマットに整形します．golangにはbytesパッケージという便利なものがあって固定長のフィールドからなる構造体に一瞬でマッピングできるんですけどRustにはどうやらなさそうなので渋々一から書きます．Rustの型システムに慣れていないのですごく苦戦しました．
```rust
pub struct DHCPPacket {
    pub op: DHCPOperationCode,
    pub htype: u8,
    pub hlen: u8,
    pub hops: u8,
    pub xid: u32,
    pub secs: u16,
    pub flags: BFlag,
    pub ciaddr: Ipv4Addr,
    pub yiaddr: Ipv4Addr,
    pub siaddr: Ipv4Addr,
    pub giaddr: Ipv4Addr,
    pub chaddr: MacAddr,
    pub options: Vec<Options>
}

pub enum DHCPOperationCode {
    Request = 1,
    Reply = 2
}

pub enum BFlag {
    Unicast = 0,
    Broadcast = 1
}
```

### オプション
次に実装するDHCPオプションタイプに基づいてenumを定義します．オプションの中身を保持したenumとして各オプションを定義しました．enumの中身の値とってくるのってmatch式しかないのかな．
```rust
pub struct DHCPOption {
    pub code: u8,
    pub data: Vec<u8>,
}

pub enum Options {
    SubnetMask(Ipv4Addr),
    RouterOption(Vec<Ipv4Addr>),
    DNSOption(Vec<Ipv4Addr>),
    IPTol(u8),
    RequestedIPAddress(Ipv4Addr),
    LeaseTime(u32),
    DHCPMessageType(MessageType),
    ServerIdentifier(Ipv4Addr),
    Message(String),
}

pub enum MessageType {
    DHCPDISCOVER = 1,
    DHCPOFFER = 2,
    DHCPREQUEST = 3,
    DHCPDECLINE = 4,
    DHCPACK = 5,
    DHCPNAK = 6,
    DHCPRELEAS = 7
}
```
### 割り当てたアドレスを格納しておくストレージ
次に用意するのは割り当て済みのアドレスとそのアドレスを割り振ったクライアントの情報を格納しておく構造体であるentryとStorageを定義します．entryには割り振ったIPアドレスとそのクライアントのMACアドレスを格納します．
```rust
pub struct Storage {
    pub entries: Vec<Entry>
}

pub struct Entry {
    pub id: u32,
    pub ip_addr: Ipv4Addr,
    pub mac_addr: MacAddr,
}
```

### サーバー
server構造体にDHCPサーバーが保持すべき情報を格納します．この構造体は複数のスレッドから参照されるため，使用する際はArcを使用します．また，Storage構造体は複数のスレッドから更新されるためMutexを使用します.
```rust
pub struct DHCPServer {
    pub addr: Ipv4Addr,
    pub port: u32,
    pub pool: Ipv4Network,
    // pub pool: Mutex<Vec<Ipv4Addr>>,
    pub storage: Mutex<Storage>,
    pub router: Ipv4Addr,
    pub subnet_mask: Ipv4Addr,
    pub dns_server: Ipv4Addr,
    pub lease_time: u32,
}
```
DHCPサーバーはUDP上で動作するためUDPソケットを開いてバインドします．以下がserve関数の雛形です．こちらのOk()のアームに処理を追加していきます．
```rust
fn handle(&self, socket: &UdpSocket, packet: &DHCPPacket) -> Result<(), failure::Error> {
        let options = packet.get_options();
        // let message_type = &options[0];
        match &options[0] {
            Options::DHCPMessageType(typ) => {
                match typ {
                    MessageType::DHCPDISCOVER => self.dhcp_discover_handle(socket, packet)?,
                    // MessageType::DHCPOFFER =>
                    MessageType::DHCPREQUEST => self.dhcp_request_handle(socket, packet)?,
                    // MessageType::DHCPDECLINE =>
                    // MessageType::DHCPACK =>
                    // MessageType::DHCPNAK =>
                    MessageType::DHCPRELEAS => self.dhcp_request_handle_release(socket, packet)?,
                    _ => return Err(failure::format_err!("Unhandlable message type"))
                }
            },
            _ => return Err(failure::format_err!("dhcp option type is not found")),
        }
        Ok(())
    }
```
#### DHCPDISCOVERを処理する
DHCPDISCOVERメッセージを受け取った場合の処理を追加します．このメッセージによってサーバーはクライアントに使用可能なアドレスを割り振ってDHCPOFFERメッセージとして返信(broadcast)します．処理内容としてはRequested IP Addressオプションをみてアドレスがセットされていればそのアドレス，セットされていなければ割り当て可能な任意のアドレスを使用可能か検索してleased_addrに格納します．その情報とその他必要なパラメータを組み立ててDHCPOFFERをブロードキャストします．
```rust
fn dhcp_discover_handle(&self, socket: &UdpSocket, packet: &DHCPPacket) -> Result<(), failure::Error> {
        println!("DHCP DISCOVER");

        let requested_address = is_requested_address(&packet.options);
        let leased_addr = self.lease_address(packet.xid, packet.chaddr, requested_address)?;
        // ignore packet.giaddr because this server don't handle relay agent
        // create DHCPOFFER message
        let reply = DHCPPacket::create_reply_packet(
            packet.xid,
            leased_addr,
            packet.giaddr,
            None,
            packet.flags,
            packet.chaddr,
            self.create_options(2)
        )?;
        println!("-------- reply packet DHCPOFFER ----------");
        println!("{:?}", packet);
        let buf = reply.decode().expect("failed to decode reply packet");
        // broadcast
        broadcast(socket, &buf)?;
        Ok(())
    }
```
lease_address関数ではstorageとpoolから割り当て可能なアドレスを選択して返します．データの取り方やイテレータの扱い，所有権などに悩まされて変なコードになってしまいました．具体的にはrequestedがOptionとして与えられるため，Someならそのアドレスが使用可能か判断して使用可能ならそのアドレスを返します．Noneならpoolとstorage，サーバーの設定などで使用不可以外のアドレスから最も小さいアドレスを返します．
```rust
fn lease_address(&self, xid: u32, chaddr: MacAddr, requested: Option<&Ipv4Addr>) -> Result<Ipv4Addr, failure::Error> {
        // lock
        let mut s = self.storage.lock().unwrap();
        let used_address = vec![self.router, self.dns_server, self.pool.network()];
        // search an entry from storage by mac address
        if let Ok(addr) = s.search_from_mac(&chaddr) {
            return Ok(addr);
        }
        // requested ip address
        if let Some(addr) = requested {
            if !self.is_available_address(*addr) {
                return Err(failure::format_err!("requested address is already used"))
            }
            match s.search_from_ip(&addr) {
                Ok(_) => {
                    println!("requested address is not available");
                    let addr = s.find_available_address(self.pool, used_address)
                                .expect("There is no available address");
                    // s.add(&Entry::new(xid, addr, chaddr));
                    return Ok(addr);
                },
                Err(_) => {
                    // requested address is available
                    // s.add(&Entry::new(xid, addr, chaddr));
                    return Ok(*addr);
                },
            }
        }
        //
        let addr = s.find_available_address(self.pool, used_address).expect("there is no available address");
        s.add(&Entry::new(xid, addr, chaddr));
        Ok(addr)
    }
```
### DHCPREQUESTを処理する
次にDHCPREQUESTメッセージを処理します．REQUESTメッセージには主な要求が二つあり，１つはDHCPOFFERに対する応答です．この場合，オプションのServer Identifierにオファーを受けるサーバーのアドレスが格納されます．もう一つは以前割り当てられていたアドレスの確認やリース期間の延長の要求です．

まずはオファーに対する応答から．これを確かめるためには受信したパケットのオプションにServer Identifierがあるかどうかを確認します．あった場合はそこにセットされているIPアドレスが自分のアドレスであるかを確認します．一致しない場合は他のサーバーを選択したということになります．一致した場合はオプションにRequested IP Addressが設定されているはずなのでその値とクライアントのMACアドレスをstorageに保存してDHCPACKメッセージを返信します．
```rust
fn dhcp_request_handle_selecting(&self, server_ip: Ipv4Addr, socket: &UdpSocket, packet: &DHCPPacket) -> Result<(), failure::Error> {
        if server_ip != self.addr {
            println!("client choose other dhcp server");
            return Ok(());
        }
        let requested_addr = is_requested_address(&packet.options).expect("requested ip address is not set");

        let mut s = self.storage.lock().expect("failed to lock storage"); // ここロックしていい？

        match s.search_from_mac(&packet.chaddr) {
            Ok(_) => {
                // update
                let entry = Entry::new(packet.xid, *requested_addr, packet.chaddr);
                s.update(&entry)?;
            },
            Err(_) => {
                // insert
                let entry = Entry::new(packet.xid, *requested_addr, packet.chaddr);
                s.add(&entry);
            }
        }
        // create DHCPACK packet
        let options = self.create_options(5);
        let reply = DHCPPacket::create_reply_packet(
            packet.xid,
            *requested_addr,
            packet.giaddr,
            None, // 埋めないといけないかも
            packet.flags,
            packet.chaddr,
            options
        )?;
        println!("-------- reply packet DHCPACK ----------");
        println!("{:?}", reply);
        let buf = reply.decode().expect("failed to decode reply packet");
        broadcast(socket, &buf)?;
        Ok(())
    }
```
次にIPアドレスの確認などのREQUESTに対する応答です．機能をかなり省略しているので基本的にDHCPNAKを返します．アドレスの確認でパケットのRequested IP Addressオプションにアドレスが設定されており，そのアドレスと保存しているアドレスが一致している場合のみDHCPACKを返します．
```rust
fn dhcp_request_handle_re(&self, socket: &UdpSocket, packet: &DHCPPacket) -> Result<(), failure::Error> {
        if let Some(addr) = is_requested_address(&packet.options) {
            // init-reboot
            println!("ININ-REBOOT");
            {
                let s = self.storage.lock().unwrap();
                match s.search_from_mac(&packet.chaddr) {
                    Ok(a) => {
                        if *addr == a {
                            let options = self.create_options(5);
                            let reply = DHCPPacket::create_reply_packet(
                                packet.xid,
                                *addr,
                                packet.giaddr,
                                None,
                                packet.flags,
                                packet.chaddr,
                                options
                            )?;
                            let buf = reply.decode().expect("failed to decode reply packet");
                            broadcast(socket, &buf)?;
                            return Ok(());
                        } else {
                            // reply DHCPACK
                            let options = self.create_options(6);
                            let reply = DHCPPacket::create_reply_packet(
                                packet.xid,
                                *addr,
                                packet.giaddr,
                                None,
                                packet.flags,
                                packet.chaddr,
                                options
                            )?;
                            let buf = reply.decode().expect("failed to decode reply packet");
                            broadcast(socket, &buf)?;
                            return Ok(());
                        }
                    },
                    Err(_) => {
                        return Ok(())
                    },
                }
            }
        } else {
            // requested address is invalid
            println!("RENEWING or REBINDING");
            let options = self.create_options(6);
            let reply = DHCPPacket::create_reply_packet(
                packet.xid,
                Ipv4Addr::new(0,0,0,0),
                packet.giaddr,
                None,
                packet.flags,
                packet.chaddr,
                options
            )?;
            let buf = reply.decode().expect("failed to decode reply packet");
            broadcast(socket, &buf)?;
            Ok(())
        }
    }
```
### DHCPRELEASを処理する
最後にDHCPRELEASを処理します．RFCにはリースされたアドレスとクライアントの情報はできるだけ保存されておくべきとありますが，今回作成しているコードでは保存が効かないので単純にstorageからデータを削除しています．
```rust
fn dhcp_request_handle_release(&self, socket: &UdpSocket, packet: &DHCPPacket) -> Result<(), failure::Error> {
        println!("DHCP RELEASE");
        // release leased ip address
        let mut s = self.storage.lock().unwrap();
        s.delete_by_ip(&packet.ciaddr)?;
        println!("delete leased ip: {:?}", packet.ciaddr);
        Ok(())
    }
```

## 実行
最低限の処理は完成したので実際に実行してみます．
### 実行結果
```
server use
---------- dhcp server start ----------
DHCPServer { addr: 192.168.10.2, port: 67, pool: Ipv4Network { addr: 192.168.10.0, prefix: 24 }, storage: Mutex { data: Storage { entries: [] } }, router: 192.168.10.1, subnet_mask: 255.255.255.0, dns_server: 8.8.8.8, lease_time: 1000000 }
---------------------------------------
received 300bytes from V4(0.0.0.0:68)
create new thread.
DHCPPacket { op: Request, htype: 1, hlen: 6, hops: 0, xid: 1571637094, secs: 0, flags: Unicast, ciaddr: 0.0.0.0, yiaddr: 0.0.0.0, siaddr: 0.0.0.0, giaddr: 0.0.0.0, chaddr: a4:4e:31:c9:84:14, options: [DHCPMessageType(DHCPREQUEST), RequestedIPAddress(192.168.10.104)] }
DHCP REQUEST
ININ-REBOOT
received 300bytes from V4(0.0.0.0:68)
create new thread.
DHCPPacket { op: Request, htype: 1, hlen: 6, hops: 0, xid: 959044153, secs: 0, flags: Unicast, ciaddr: 0.0.0.0, yiaddr: 0.0.0.0, siaddr: 0.0.0.0, giaddr: 0.0.0.0, chaddr: a4:4e:31:c9:84:14, options: [DHCPMessageType(DHCPDISCOVER), RequestedIPAddress(192.168.10.104)] }
DHCP DISCOVER
-------- reply packet DHCPOFFER ----------
DHCPPacket { op: Request, htype: 1, hlen: 6, hops: 0, xid: 959044153, secs: 0, flags: Unicast, ciaddr: 0.0.0.0, yiaddr: 0.0.0.0, siaddr: 0.0.0.0, giaddr: 0.0.0.0, chaddr: a4:4e:31:c9:84:14, options: [DHCPMessageType(DHCPDISCOVER), RequestedIPAddress(192.168.10.104)] }
received 300bytes from V4(0.0.0.0:68)
create new thread.
DHCPPacket { op: Request, htype: 1, hlen: 6, hops: 0, xid: 959044153, secs: 0, flags: Unicast, ciaddr: 0.0.0.0, yiaddr: 0.0.0.0, siaddr: 0.0.0.0, giaddr: 0.0.0.0, chaddr: a4:4e:31:c9:84:14, options: [DHCPMessageType(DHCPREQUEST), ServerIdentifier(192.168.10.2), RequestedIPAddress(192.168.10.104)] }
DHCP REQUEST
-------- reply packet DHCPACK ----------
DHCPPacket { op: Reply, htype: 1, hlen: 6, hops: 0, xid: 959044153, secs: 0, flags: Unicast, ciaddr: 0.0.0.0, yiaddr: 192.168.10.104, siaddr: 0.0.0.0, giaddr: 0.0.0.0, chaddr: a4:4e:31:c9:84:14, options: [DHCPMessageType(DHCPACK), ServerIdentifier(192.168.10.2), SubnetMask(255.255.255.0), RouterOption([192.168.10.1]), DNSOption([8.8.8.8]), LeaseTime(1000000)] }
```
なんとかDHCPDISCOVERからDHCPACKまでの流れが表示されています．DNSの設定やルーターの設定が適当なので実際のネットワークでは使えませんがクライアントとして用意したLinuxマシンにもアドレスが割り振られていました．(写真撮ったのになぜかアップロードできなかった)

## まとめ
冒頭で紹介した[Rustで始めるネットワークプログラミング](https://www.amazon.co.jp/gp/product/B07SW2GXVF/ref=ppx_yo_dt_b_d_asin_title_o00?ie=UTF8&psc=1)をRustの練習のために写経していた時にDHCPサーバーを作成する章があったのでせっかくだから自分で作ってみようと思い書き始めました．Rustはイテレータを使ってデータの操作がすっきり書けるのがいいですね．最初は型システムに苦戦しましたが楽しく書けました．(所有権あたりを対して意識しなかったのでもっと勉強しないと)

DHCPの仕様が思ってたより複雑でした．RFCを読みながら実装するのはネットワークについて学ぶにもプログラムを記述するのにも勉強になります．
