import 'package:flutter_contacts/flutter_contacts.dart' as fc;
import 'package:uuid/uuid.dart';

import 'occasion_service.dart';

/// Result of asking for contacts access.
enum ContactsAccess { granted, denied, blocked }

/// Reads birthdays from the address book — only after the user opted in on
/// the explanation screen. Reads display names and birthday events, nothing
/// else; the result keeps only a name and a day (no contact ids, numbers or
/// photos), stored on this device.
class ContactsBirthdays {
  const ContactsBirthdays();

  /// Asks the OS for read access (shows the system dialog the first time).
  Future<ContactsAccess> requestAccess() async {
    try {
      final s = await fc.FlutterContacts.permissions.request(fc.PermissionType.read);
      return switch (s) {
        fc.PermissionStatus.granted || fc.PermissionStatus.limited => ContactsAccess.granted,
        fc.PermissionStatus.permanentlyDenied || fc.PermissionStatus.restricted => ContactsAccess.blocked,
        _ => ContactsAccess.denied,
      };
    } catch (_) {
      return ContactsAccess.denied;
    }
  }

  /// Opens the system settings page for the app (after a permanent denial).
  Future<void> openSettings() => fc.FlutterContacts.permissions.openSettings();

  /// Every contact birthday as a [Birthday] flagged `fromContacts`.
  Future<List<Birthday>> read() async {
    final contacts = await fc.FlutterContacts.getAll(properties: {fc.ContactProperty.event});
    final out = <Birthday>[];
    for (final c in contacts) {
      final name = c.displayName?.trim() ?? '';
      if (name.isEmpty) continue;
      for (final e in c.events) {
        if (e.label.label != fc.EventLabel.birthday) continue;
        if (e.month < 1 || e.month > 12 || e.day < 1 || e.day > 31) continue;
        out.add(Birthday(
          id: const Uuid().v4(),
          name: name,
          month: e.month,
          day: e.day,
          year: e.year,
          fromContacts: true,
        ));
        break; // one birthday per person
      }
    }
    return out;
  }
}
