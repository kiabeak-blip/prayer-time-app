import 'dart:convert';
import 'package:http/http.dart' as http;
import '../firebase_options.dart';
import '../models/chat_message.dart';
import 'auth_service.dart';

class ChatService {
  static Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        if (AuthService.instance.idToken != null)
          'Authorization': 'Bearer ${AuthService.instance.idToken}',
      };

  /// Fetch the latest [limit] messages, newest last (ascending time).
  static Future<List<ChatMessage>> getMessages({int limit = 60}) async {
    final res = await http.post(
      Uri.parse(FirebaseConfig.runQuery()),
      headers: _headers,
      body: jsonEncode({
        'structuredQuery': {
          'from': [
            {'collectionId': 'chat_messages'}
          ],
          'orderBy': [
            {'field': {'fieldPath': 'timestamp'}, 'direction': 'DESCENDING'}
          ],
          'limit': limit,
        }
      }),
    );
    if (res.statusCode != 200) {
      throw Exception('Chat load failed (${res.statusCode}): ${res.body}');
    }
    final list = jsonDecode(res.body) as List;
    final messages = list
        .where((e) => e['document'] != null)
        .map((e) => ChatMessage.fromFirestore(
            e['document'] as Map<String, dynamic>))
        .toList();
    // Reverse so oldest is first (chat order)
    return messages.reversed.toList();
  }

  /// Send a message.
  static Future<void> sendMessage(ChatMessage message) async {
    final res = await http.post(
      Uri.parse(FirebaseConfig.collection('chat_messages')),
      headers: _headers,
      body: jsonEncode(message.toFirestoreFields()),
    );
    if (res.statusCode != 200) {
      throw Exception('Send failed (${res.statusCode}): ${res.body}');
    }
  }

  /// Delete a message by id (admin/superadmin only).
  static Future<void> deleteMessage(String id) async {
    final url = '${FirebaseConfig.collection('chat_messages')}/$id';
    final res = await http.delete(Uri.parse(url), headers: _headers);
    if (res.statusCode != 200 && res.statusCode != 204) {
      throw Exception('Delete failed (${res.statusCode})');
    }
  }
}
