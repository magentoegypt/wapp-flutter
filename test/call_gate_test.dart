import 'package:clickalize/features/calls/domain/call.dart';
import 'package:flutter_test/flutter_test.dart';

/// Which gate closed, and why the three must not be collapsed.
///
/// The capability endpoint reports them separately on purpose. `enabled` is a
/// workspace switch someone can flip; `outboundSupported` is Meta refusing
/// business-initiated calls from this number and is not fixable at all; and
/// `withinBusinessHours` is time-of-day and clears on its own. Telling an agent
/// to check their settings when Meta is the blocker sends them hunting for a
/// switch that would not help — and the business-hours case used to fall
/// through to the country message and name a restriction that was not in force.
CallCapability _cap({
  bool enabled = true,
  bool outbound = true,
  bool hoursEnabled = false,
  bool withinHours = true,
  bool canPlace = true,
  String? reason,
}) =>
    CallCapability(
      enabled: enabled,
      outboundSupported: outbound,
      outboundRestrictedReason: reason,
      businessHoursEnabled: hoursEnabled,
      withinBusinessHours: withinHours,
      canPlaceCall: canPlace,
    );

void main() {
  test('nothing is reported when a call can be placed', () {
    expect(_cap().blockedBy, isNull);
  });

  test('the workspace switch wins — it is the one the user can fix', () {
    expect(
      _cap(enabled: false, outbound: false, canPlace: false).blockedBy,
      CallBlock.workspaceDisabled,
    );
  });

  test('this workspace: Meta blocks the number', () {
    // The live capability, verbatim from the artifact.
    final CallCapability c = _cap(
      outbound: false,
      hoursEnabled: true,
      reason: 'USA / Canada',
      canPlace: false,
    );
    expect(c.blockedBy, CallBlock.countryRestricted);
    expect(c.outboundRestrictedReason, 'USA / Canada');
  });

  test('outside business hours is its own answer', () {
    // This is the case that used to render the country message with a null
    // reason — naming a restriction that was not the one in force, about a
    // block that clears by itself in an hour.
    expect(
      _cap(hoursEnabled: true, withinHours: false, canPlace: false).blockedBy,
      CallBlock.outsideBusinessHours,
    );
  });

  test('hours only count when the workspace keeps them', () {
    // withinBusinessHours is meaningless with the feature off, so it must not
    // be blamed for a block it did not cause.
    expect(
      _cap(hoursEnabled: false, withinHours: false, canPlace: false).blockedBy,
      CallBlock.unknown,
    );
  });

  test('a refusal with every gate open is not explained away', () {
    // canPlaceCall is the server's conjunction and it is authoritative. If it
    // says no while the parts say yes, the honest answer is that we do not
    // know — not a guess at one of the three.
    expect(_cap(canPlace: false).blockedBy, CallBlock.unknown);
  });
}
