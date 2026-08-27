import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lifemate_client/lifemate_client.dart';

void main(){test('support inbox maps only consumer-safe fields',()async{final api=LifeMateSupportApi(baseUri:Uri.parse('https://example.test'),accessToken:()=> 'token',httpClient:MockClient((request)async{expect(request.headers['Authorization'],'Bearer token');return http.Response(jsonEncode({'items':[{'ticketId':'t1','ticketNumber':42,'status':'Open','productCode':'wellmate','unreadStaffCount':2,'latestMessageBody':'hello','lastActivityAtUtc':'2026-08-27T12:00:00Z'}]}),200);}));final items=await api.conversations();expect(items.single.ticketNumber,42);expect(items.single.unreadStaffCount,2);api.close();});
test('send keeps caller supplied client id for retry idempotency',()async{String? id;final api=LifeMateSupportApi(baseUri:Uri.parse('https://example.test'),accessToken:()=> 'token',httpClient:MockClient((request)async{id=(jsonDecode(request.body) as Map<String,dynamic>)['clientMessageId']?.toString();return http.Response('{"ticketId":"11111111-1111-4111-8111-111111111111","messageId":"22222222-2222-4222-8222-222222222222"}',201);}));await api.send('11111111-1111-4111-8111-111111111111','retry me',clientMessageId:'33333333-3333-4333-8333-333333333333');expect(id,'33333333-3333-4333-8333-333333333333');api.close();});}
