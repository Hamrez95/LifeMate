import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app_config.dart';
import 'lifemate_api_client.dart';

class LifeMateSupportConversation {
  const LifeMateSupportConversation({required this.ticketId, required this.ticketNumber, required this.status, required this.productCode, required this.unreadStaffCount, required this.latestMessageBody, required this.lastActivityAtUtc});
  factory LifeMateSupportConversation.fromJson(Map<String,dynamic> json) => LifeMateSupportConversation(ticketId: json['ticketId']?.toString() ?? '', ticketNumber: int.tryParse(json['ticketNumber']?.toString() ?? '') ?? 0, status: json['status']?.toString() ?? 'Open', productCode: json['productCode']?.toString(), unreadStaffCount: int.tryParse(json['unreadStaffCount']?.toString() ?? '') ?? 0, latestMessageBody: json['latestMessageBody']?.toString(), lastActivityAtUtc: DateTime.tryParse(json['lastActivityAtUtc']?.toString() ?? ''));
  final String ticketId; final int ticketNumber; final String status; final String? productCode; final int unreadStaffCount; final String? latestMessageBody; final DateTime? lastActivityAtUtc;
}

class LifeMateSupportAttachment {
  const LifeMateSupportAttachment({required this.attachmentId, required this.fileName, required this.contentType, required this.sizeBytes, required this.scanStatus});
  factory LifeMateSupportAttachment.fromJson(Map<String,dynamic> json) => LifeMateSupportAttachment(attachmentId: json['attachmentId']?.toString() ?? '', fileName: json['fileName']?.toString() ?? '', contentType: json['contentType']?.toString() ?? '', sizeBytes: int.tryParse(json['sizeBytes']?.toString() ?? '') ?? 0, scanStatus: json['scanStatus']?.toString() ?? 'Pending');
  final String attachmentId, fileName, contentType, scanStatus; final int sizeBytes;
  bool get downloadable => scanStatus == 'Available';
}

class LifeMateSupportMessage {
  const LifeMateSupportMessage({required this.messageId, required this.senderKind, required this.body, required this.createdAtUtc, required this.attachments});
  factory LifeMateSupportMessage.fromJson(Map<String,dynamic> json) => LifeMateSupportMessage(messageId: json['messageId']?.toString() ?? '', senderKind: json['senderKind']?.toString() ?? '', body: json['body']?.toString() ?? '', createdAtUtc: DateTime.tryParse(json['createdAtUtc']?.toString() ?? '') ?? DateTime.fromMillisecondsSinceEpoch(0, isUtc:true), attachments: (json['attachments'] as List<dynamic>? ?? const []).whereType<Map>().map((e)=>LifeMateSupportAttachment.fromJson(Map<String,dynamic>.from(e))).toList(growable:false));
  final String messageId, senderKind, body; final DateTime createdAtUtc; final List<LifeMateSupportAttachment> attachments;
  bool get fromUser => senderKind == 'User';
}

typedef LifeMateSupportTokenProvider = String? Function();

class LifeMateSupportApi {
  LifeMateSupportApi({required Uri baseUri, required LifeMateSupportTokenProvider accessToken, http.Client? httpClient}) : _baseUri=baseUri, _accessToken=accessToken, _http=httpClient ?? http.Client();
  factory LifeMateSupportApi.fromEnvironment({http.Client? httpClient}) { final config=AppConfig.fromEnvironment(); return LifeMateSupportApi(baseUri: config.apiBaseUri, accessToken: ()=>Supabase.instance.client.auth.currentSession?.accessToken, httpClient:httpClient); }
  final Uri _baseUri; final LifeMateSupportTokenProvider _accessToken; final http.Client _http; static const _timeout=Duration(seconds:20);

  Future<List<LifeMateSupportConversation>> conversations() async { final value=_object(await _request('GET','/api/v1/support/conversations')); return (value['items'] as List<dynamic>? ?? const []).whereType<Map>().map((e)=>LifeMateSupportConversation.fromJson(Map<String,dynamic>.from(e))).toList(growable:false); }
  Future<Map<String,dynamic>> open({required String productCode, required String body, String category='general', String? clientMessageId}) async => _object(await _request('POST','/api/v1/support/conversations', body:{'productCode':productCode,'category':category,'body':body,'clientMessageId':clientMessageId ?? LifeMateApiClient.createClientRequestId()}));
  Future<List<LifeMateSupportMessage>> messages(String ticketId,{DateTime? afterAt}) async { final suffix=afterAt==null?'':'?afterAt=${Uri.encodeQueryComponent(afterAt.toUtc().toIso8601String())}'; final value=_object(await _request('GET','/api/v1/support/conversations/$ticketId$suffix')); return (value['items'] as List<dynamic>? ?? const []).whereType<Map>().map((e)=>LifeMateSupportMessage.fromJson(Map<String,dynamic>.from(e))).toList(growable:false); }
  Future<Map<String,dynamic>> send(String ticketId,String body,{String? clientMessageId}) async => _object(await _request('POST','/api/v1/support/conversations/$ticketId/messages',body:{'body':body,'clientMessageId':clientMessageId ?? LifeMateApiClient.createClientRequestId()}));
  Future<void> markRead(String ticketId,String messageId) async { await _request('POST','/api/v1/support/conversations/$ticketId/read',body:{'messageId':messageId}); }
  Future<Map<String,dynamic>> upload(String ticketId,String messageId,{required String fileName,required String contentType,required Uint8List bytes}) async => _object(await _request('PUT','/api/v1/support/conversations/$ticketId/messages/$messageId/attachments',bytes:bytes,extraHeaders:{'Content-Type':contentType,'x-file-name':fileName}));
  Future<Uri> attachmentDownload(String ticketId,String attachmentId) async { final value=_object(await _request('GET','/api/v1/support/conversations/$ticketId/attachments/$attachmentId/download')); final uri=Uri.tryParse(value['signedUrl']?.toString() ?? ''); if(uri==null || !uri.hasScheme) throw const FormatException('Support attachment URL is invalid.'); return uri; }

  Future<dynamic> _request(String method,String path,{Map<String,dynamic>? body,Uint8List? bytes,Map<String,String>? extraHeaders}) async { final token=_accessToken(); if(token==null || token.isEmpty) throw const LifeMateApiException(statusCode:401,code:'session_missing',message:'Authentication session is missing.'); final uri=_baseUri.replace(path:'${_baseUri.path.replaceFirst(RegExp(r'/$'),'')}${path.split('?').first}',query:path.contains('?')?path.split('?').skip(1).join('?'):null); final headers=<String,String>{'Accept':'application/json','Authorization':'Bearer $token',...?(extraHeaders),if(body!=null)'Content-Type':'application/json',if(method=='POST')'Idempotency-Key':LifeMateApiClient.createClientRequestId()}; try { final response=switch(method){'GET'=>await _http.get(uri,headers:headers).timeout(_timeout),'POST'=>await _http.post(uri,headers:headers,body:jsonEncode(body)).timeout(_timeout),'PUT'=>await _http.put(uri,headers:headers,body:bytes).timeout(_timeout),_=>throw ArgumentError.value(method,'method')}; final decoded=response.body.trim().isEmpty?null:jsonDecode(response.body); if(response.statusCode>=200 && response.statusCode<300)return decoded; final problem=decoded is Map?Map<String,dynamic>.from(decoded):const <String,dynamic>{}; throw LifeMateApiException(statusCode:response.statusCode,code:problem['code']?.toString() ?? 'support_request_failed',message:problem['detail']?.toString() ?? problem['message']?.toString() ?? 'Support request failed.'); } on TimeoutException { throw const LifeMateApiException(statusCode:0,code:'network_timeout',message:'Support request timed out.'); } on http.ClientException { throw const LifeMateApiException(statusCode:0,code:'network_unavailable',message:'Support service is unavailable.'); } }
  static Map<String,dynamic> _object(dynamic value){ if(value is! Map) throw const FormatException('Support API returned a non-object payload.'); return Map<String,dynamic>.from(value); }
  void close()=>_http.close();
}
