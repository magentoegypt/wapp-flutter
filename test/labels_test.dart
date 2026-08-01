import 'package:clickalize/features/conversation_actions/domain/action_models.dart';
import 'package:clickalize/features/conversation_actions/presentation/screens/manage_labels_screen.dart';
import 'package:flutter_test/flutter_test.dart';

/// Manage labels is the only screen in the app where doing nothing destroys
/// data.
///
/// `setLabels` **replaces** the set, so an unticked box is a removal. The screen
/// took the applied labels as a constructor argument and the one call site
/// pushed the route without them — so it opened with every box clear on a
/// conversation that had labels, and Save stripped them. Nothing errored; the
/// labels were simply gone.
///
/// The applied set is now resolved from the contact instead of trusted from the
/// caller, and these pin the matching, because the identifiers on the two sides
/// are not guaranteed to be the same shape.
void main() {
  const List<ConversationLabel> known = <ConversationLabel>[
    ConversationLabel(uid: 'l1', name: 'amira'),
    ConversationLabel(uid: 'l2', name: 'Egypt'),
    ConversationLabel(uid: 'l3', name: 'hassan. yousra'),
  ];

  test('a label carried by name is ticked', () {
    // What the live payload does: the contact lists names, the vocabulary is
    // keyed by uid. Comparing them directly ticks nothing.
    expect(
      appliedLabelUids(known, <String>['amira'], const <String>[]),
      <String>{'l1'},
    );
  });

  test('a label carried by uid is ticked', () {
    expect(
      appliedLabelUids(known, <String>['l2'], const <String>[]),
      <String>{'l2'},
    );
  });

  test('case and padding do not lose a label', () {
    expect(
      appliedLabelUids(known, <String>['  EGYPT '], const <String>[]),
      <String>{'l2'},
    );
    expect(
      appliedLabelUids(known, <String>['Hassan. Yousra'], const <String>[]),
      <String>{'l3'},
    );
  });

  test('a caller hint is honoured and merged, not replaced', () {
    expect(
      appliedLabelUids(known, <String>['amira'], const <String>['l2']),
      <String>{'l1', 'l2'},
    );
  });

  test('an unknown label is dropped rather than guessed at', () {
    // It cannot be shown as ticked, so preserving it would contradict the
    // screen — and inventing a uid would send one the workspace rejects.
    expect(
      appliedLabelUids(known, <String>['deleted-label'], const <String>[]),
      isEmpty,
    );
    expect(appliedLabelUids(known, <String>[''], const <String>[]), isEmpty);
  });

  test('no labels means no ticks', () {
    expect(
      appliedLabelUids(known, const <String>[], const <String>[]),
      isEmpty,
    );
  });
}
