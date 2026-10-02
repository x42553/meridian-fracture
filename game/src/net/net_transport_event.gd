class_name NetTransportEvent
extends RefCounted
## One transport event (docs/spec/net.md 3.2). Produced by NetTransport.poll(), consumed via take_events().

enum Kind { CONNECTED = 1, DISCONNECTED = 2, PACKET = 3 }

var kind: int = Kind.PACKET
## Transport-level id: the host is always 1; a client sees the server as 1; remote clients get 2, 3, ... (never reused per transport instance).
var peer_id: int = 0
## PACKET only: the channel it arrived on.
var channel: int = 0
## PACKET only: the whole message (ENet reassembles fragments).
var data: PackedByteArray = PackedByteArray()
## CONNECTED: connect_data supplied by the remote. DISCONNECTED: disconnect code (0 = transport timeout / none).
var code: int = 0
## CONNECTED on the listening side: the remote IP string.
var address: String = ""


static func connected(peer_id_: int, code_: int, address_: String) -> NetTransportEvent:
	var e: NetTransportEvent = NetTransportEvent.new()
	e.kind = Kind.CONNECTED
	e.peer_id = peer_id_
	e.code = code_
	e.address = address_
	return e


static func disconnected(peer_id_: int, code_: int) -> NetTransportEvent:
	var e: NetTransportEvent = NetTransportEvent.new()
	e.kind = Kind.DISCONNECTED
	e.peer_id = peer_id_
	e.code = code_
	return e


static func packet(peer_id_: int, channel_: int, data_: PackedByteArray) -> NetTransportEvent:
	var e: NetTransportEvent = NetTransportEvent.new()
	e.kind = Kind.PACKET
	e.peer_id = peer_id_
	e.channel = channel_
	e.data = data_
	return e
