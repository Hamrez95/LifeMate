import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'app_config.dart';
import 'lifemate_api_client.dart';

class LifeMateCompanionCareApi {
  LifeMateCompanionCareApi({required Uri baseUri,required String? Function() accessToken,http.Client? httpClient}):_baseUri=baseUri,_accessToken=accessToken,_http=httpClient??http.Client();
  factory LifeMateCompanionCareApi.fromEnvironment({http.Client? httpClient}){final config=AppConfig.fromEnvironment();return LifeMateCompanionCareApi(baseUri:config.apiBaseUri,accessToken:()=>Supabase.instance.client.auth.currentSession?.accessToken,httpClient:httpClient);}
  final Uri _baseUri;final String? Function() _accessToken;final http.Client _http;static const _timeout=Duration(seconds:20);
  Future<Map<String,dynamic>> recordImpression({required String patientUserId,required String guidanceId,required String contentVersion,required String category})async{
    final token=_accessToken();if(token==null||token.isEmpty)throw const LifeMateApiException(statusCode:401,code:'session_missing',message:'Authentication session is missing.');
    final base=_baseUri.toString().replaceFirst(RegExp(r'/+$'),'');final uri=Uri.parse('$base/api/v1/care/patients/$patientUserId/women-calendar/support-actions');
    try{final response=await _http.post(uri,headers:{'Accept':'application/json','Authorization':'Bearer $token','Content-Type':'application/json','Idempotency-Key':LifeMateApiClient.createClientRequestId()},body:jsonEncode({'actionType':'guidance_impression','guidanceId':guidanceId,'contentVersion':contentVersion,'category':category})).timeout(_timeout);dynamic decoded;if(response.body.isNotEmpty)decoded=jsonDecode(response.body);if(response.statusCode<200||response.statusCode>=300){final p=decoded is Map?Map<String,dynamic>.from(decoded):const <String,dynamic>{};throw LifeMateApiException(statusCode:response.statusCode,code:p['code']?.toString()??'request_failed',message:p['detail']?.toString()??p['message']?.toString()??'Companion guidance impression failed.');}if(decoded is! Map)throw const FormatException('Companion guidance response must be an object.');return Map<String,dynamic>.from(decoded);}on TimeoutException{throw const LifeMateApiException(statusCode:0,code:'network_timeout',message:'Companion guidance request timed out.');}on http.ClientException{throw const LifeMateApiException(statusCode:0,code:'network_unavailable',message:'Companion guidance service is unavailable.');}
  }
  void close()=>_http.close();
}
