import 'dart:convert';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:crypto/crypto.dart';
import 'api_client.dart';

class MatchedContact {
  final String id;
  final String username;
  final String? profilePictureUrl;
  final String? azamanId;

  MatchedContact({required this.id, required this.username, this.profilePictureUrl, this.azamanId});

  factory MatchedContact.fromJson(Map<String, dynamic> json) => MatchedContact(
    id: json['id'].toString(),
    username: json['username'].toString(),
    profilePictureUrl: json['profilePictureUrl']?.toString(),
    azamanId: json['azamanId']?.toString(),
  );
}

class RecentContact {
  final String friendshipId;
  final String userId;
  final String username;
  final String? profilePictureUrl;
  final DateTime updatedAt;

  RecentContact({required this.friendshipId, required this.userId, required this.username, this.profilePictureUrl, required this.updatedAt});

  factory RecentContact.fromJson(Map<String, dynamic> json) => RecentContact(
    friendshipId: json['friendshipId'].toString(),
    userId: json['userId'].toString(),
    username: json['username'].toString(),
    profilePictureUrl: json['profilePictureUrl']?.toString(),
    updatedAt: DateTime.tryParse(json['updatedAt']?.toString() ?? '') ?? DateTime.now(),
  );
}

class ContactService {
  ContactService._();
  static final ContactService instance = ContactService._();
 
  // Hash on-device BEFORE sending -- raw numbers never leave the phone.
  String _hashPhone(String rawPhone) {
    final normalized = rawPhone.replaceAll(RegExp(r'[^0-9]'), '');
    return sha256.convert(utf8.encode(normalized)).toString();
  }
 
  Future<List<MatchedContact>> syncDeviceContacts() async {
    final permission = await FlutterContacts.requestPermission();
    if (!permission) return [];
    final deviceContacts = await FlutterContacts.getContacts(withProperties: true);
    final hashes = <String>{};
    for (final c in deviceContacts) {
      for (final p in c.phones) { hashes.add(_hashPhone(p.number)); }
    }
    if (hashes.isEmpty) return [];
 
    final res = await apiClient.post('/contacts/sync', {'hashedPhones': hashes.toList()});
    if (res.statusCode != 200) return [];
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    return (body['matches'] as List? ?? [])
      .map((m) => MatchedContact.fromJson(m as Map<String, dynamic>)).toList();
  }
 
  Future<List<RecentContact>> getRecent() async {
    final res = await apiClient.get('/contacts/recent');
    if (res.statusCode != 200) return [];
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    return (body['recent'] as List? ?? [])
      .map((r) => RecentContact.fromJson(r as Map<String, dynamic>)).toList();
  }
 
  Future<String> getInviteLink() async {
    final res = await apiClient.get('/contacts/invite');
    return (jsonDecode(res.body) as Map<String, dynamic>)['link']?.toString() ?? '';
  }
}
