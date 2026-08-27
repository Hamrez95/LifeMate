import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;

class LifeMateSupportMessage {
  const LifeMateSupportMessage({required this.id, required this.body, required this.createdAtUtc, required this.fromUser});
  factory LifeMateSupportMessage.fromJson(Map<String,dynamic> json) => LifeMateSupportMessage(id: json['id']?.toString() ?? '', body: json['body']?.toString() ?? '', createdAtUtc: DateTime.parse(json['createdAtUtc'].toString()), fromUser: json['senderType']?.toString() == 'User');
  final String id; final String body; final DateTime createdAtUtc; final bool fromUser;
}

class LifeMateSupportApi {
  LifeMateSupportApi({required this.baseUri, required this.accessToken, http.Client? client}) : _client = client ?? http.Client();
  final Uri baseUri; final Future<String> Function() accessToken; final http.Client _client;
  Future<Map<String,String>> _headers() async => {'authorization':'Bearer ${await accessToken()}','content-type':'application/json'};
  Uri _uri(String path,[Map<String,String>? query]) => baseUri.replace(path:path,queryParameters:query);
  Future<Map<String,dynamic>> open({String? productCode,String category='general',required String body,required String clientMessageId}) async => _json(await _client.post(_uri('/api/v1/support/conversations'),headers:await _headers(),body:jsonEncode({'productCode':productCode,'category':category,'body':body,'clientMessageId':clientMessageId})));
  Future<List<LifeMateSupportMessage>> messages(String conversationId,{String? afterAt,int limit=50}) async { final data=_json(await _client.get(_uri('/api/v1/support/conversations/$conversationId',{'limit':'$limit',if(afterAt!=null)'afterAt':afterAt}),headers:await _headers())); return (data['items'] as List? ?? const []).whereType<Map>().map((e)=>LifeMateSupportMessage.fromJson(Map<String,dynamic>.from(e))).toList(growable:false); }
  Future<Map<String,dynamic>> send(String conversationId,{required String body,required String clientMessageId}) async => _json(await _client.post(_uri('/api/v1/support/conversations/$conversationId/messages'),headers:await _headers(),body:jsonEncode({'body':body,'clientMessageId':clientMessageId})));
  Future<void> markRead(String conversationId,String messageId) async { _json(await _client.post(_uri('/api/v1/support/conversations/$conversationId/read'),headers:await _headers(),body:jsonEncode({'messageId':messageId}))); }
  Future<Map<String,dynamic>> upload(String conversationId,String messageId,{required String fileName,required String contentType,required Uint8List bytes}) async { final h=await _headers(); h['content-type']=contentType; h['x-file-name']=fileName; final request=http.Request('PUT',_uri('/api/v1/support/conversations/$conversationId/messages/$messageId/attachments'))..headers.addAll(h)..bodyBytes=bytes; return _json(await http.Response.fromStream(await _client.send(request))); }
  Future<Uri> attachmentDownload(String conversationId,String attachmentId) async { final data=_json(await _client.get(_uri('/api/v1/support/conversations/$conversationId/attachments/$attachmentId/download'),headers:await _headers())); return Uri.parse(data['signedUrl'].toString()); }
  Map<String,dynamic> _json(http.Response response) { Map<String,dynamic> body={}; if(response.body.isNotEmpty){ final decoded=jsonDecode(response.body); if(decoded is Map) body=Map<String,dynamic>.from(decoded); } if(response.statusCode<200||response.statusCode>=300) throw LifeMateSupportException(response.statusCode,body['code']?.toString() ?? 'support_request_failed'); return body; }
}
class LifeMateSupportException implements Exception { const LifeMateSupportException(this.statusCode,this.code); final int statusCode; final String code; }
