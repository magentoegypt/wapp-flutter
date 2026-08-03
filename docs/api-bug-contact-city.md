# `contact_city` is accepted, then lost

**Reported from:** Clickalize mobile app (Flutter), build 1062, 3 Aug 2026
**Backend checkout when investigated:** `whatsjet` @ `11b40e1` (`main`, in sync
with `origin/main` at the time)
**Severity:** data loss, silent — the write is accepted and returns 200

---

## Summary

`contact_city` can be sent on both `POST /api/v1/contacts` and
`PUT /api/v1/contacts/{uid}`. Both requests succeed. The value is never
returned by `GET /api/v1/contacts/{uid}`, which is the only endpoint that
serialises city at all.

From a client there is no way to tell this apart from "this contact has no
city", because the field is absent rather than empty.

I could not determine whether the failure is in the **write** (`__data` not
persisting) or the **read** (`shape()` not finding it). Both code paths read
correct to me. Settling it needs a look at the stored row, which I can't do —
production isn't reachable from this machine and the local `wapp` database is
a different, non-running instance.

---

## Reproduction (device-verified, twice, two different paths)

### Path A — create

1. `POST /api/v1/contacts` with `contact_city: "Cairo"` (plus first/last name,
   `phone_number`, `country`, `language_code`, `contact_tags`,
   `contact_groups`, `custom_input_fields`)
2. 200. Contact created and appears in the list.
3. `GET /api/v1/contacts/{uid}` → **no `city` key**.

Everything else in that same request round-tripped correctly: name, phone,
country (Egypt), language (`en`), tags (`qa`), and group membership
(`test group`).

### Path B — update

1. Existing contact `201020104267`, no city set.
2. `PUT /api/v1/contacts/{uid}` with `contact_city: "Cairo"`, all other fields
   resent at their current values.
3. 200, no error.
4. `GET /api/v1/contacts/{uid}` → **no `city` key**.
5. **Force-stopped the app**, relaunched, refetched → still no `city`.
6. Reopened the edit form → City prefills empty.

Step 5 is the important one: it rules out any client-side caching. This is a
cold process, a fresh token-authenticated `GET`, and the value is not there.

---

## Ruled out

- **The client not sending it.** Pinned by a unit test asserting the request
  body contains `contact_city` (`test/contact_create_test.dart`), and the
  field visibly held `Cairo` on screen immediately before Save in both paths.
- **Client-side caching.** See step 5 above.
- **The request failing.** Both returned 200; the client throws on non-2xx and
  would have surfaced an error.
- **A general problem with the endpoint.** Name, country, language, email,
  tags and groups all round-trip correctly through the *same* two calls.
- **`__data` not being cast.** Both `ContactModel`s declare
  `'__data' => 'array'` in `$casts` — the Yantrana base and the Wapp subclass.
- **The Wapp engine not inheriting the write.** `App\Wapp\...\ContactEngine`
  extends `App\Yantrana\...\ContactEngine` and overrides neither
  `processContactCreate` nor `processContactUpdate`, so it inherits
  `storeContactContext()`.

---

## Code path

City is **not a column**. It lives in the contact's `__data` JSON blob.

**Write** — `app/Yantrana/Components/Contact/ContactEngine.php:1206`

```php
protected function storeContactContext($contact, array $inputData): void
{
    $city = trim((string) ($inputData['contact_city'] ?? ''));
    ...
    $contact->__data = array_merge($contact->__data ?: [], [
        'contact_city' => $city ?: null,
        'city' => $city ?: null,
        ...
    ]);
    $contact->save();
}
```

Called from both:
- `:284` inside `processContactCreate()` (`:268`)
- `:509` inside `processContactUpdate()` (`:449`)

**Read** — `app/Wapp/Components/MobileApi/Controllers/ContactApiController.php:423`

```php
if ($detailed) {
    $data = $c->__data ?? [];
    $out['city'] = $data['contact_city'] ?? ($data['city'] ?? null);
```

`GET /contacts/{uid}` calls `shape($contact, true)` (`:157`), so `$detailed`
is satisfied.

---

## Suggested diagnostics

The decisive question is what is actually in the column. With DB access:

```sql
SELECT _id, first_name, wa_id, __data
FROM contacts
WHERE wa_id = '201020104267';
```

- **`__data` contains `contact_city`** → the write is fine; the bug is in the
  read (`shape()`), or `$c->__data` is arriving as a raw string rather than an
  array on that particular query path (e.g. a `select()` that omits the column,
  or a model instance that bypasses the cast).
- **`__data` is null / has no `contact_city`** → the write is being lost.
  Then check whether `$contact->save()` at `ContactEngine:1219` actually
  issues an UPDATE. Worth checking `$fillable` — the Yantrana `ContactModel`
  declares `protected $fillable = []`, which is empty; if anything in that
  path routes through mass assignment rather than direct attribute set, it
  would be silently dropped.
- **`__data` contains it but under a different key** → `shape()` reads
  `contact_city` then `city`; anything else is missed.

A second probe that separates write from read cheaply: set a city from the
**web console** on a test contact, then call `GET /api/v1/contacts/{uid}`. If
the console's value comes back, the read is fine and the API write is the
problem. If it doesn't, the read is the problem.

---

## Related findings

These came out of the same investigation. None of them block the app — it now
works around each — but they are all live in the API, and the workarounds are
in client code where they don't belong.

### 1. `contact_city` is not seeded on partial update — data loss by omission

`ContactApiController:233`:

```php
$payload = $request->all() + [
    'first_name'  => $contact->first_name,
    'last_name'   => $contact->last_name,
    'email'       => $contact->email,
    'language_code' => $contact->language_code,
    'country'     => $contact->countries__id,
    'custom_input_fields' => [],
];
```

Five fields are seeded from the current row so a partial `PUT` preserves them.
**`contact_city` is not one of them** — but `storeContactContext()` rewrites
`__data` from `$inputData['contact_city'] ?? ''` on every update. So a `PUT`
that omits it stores `null`.

Net effect: renaming a contact erases their city. Independent of the bug
above, and it will still be a bug after that one is fixed.

Same shape, two more keys:

- **`contact_tags`** — `syncContactTags(..., $replaceExisting: true)` at
  `ContactEngine:510`. Omit it, every tag is cleared.
- **`contact_groups`** — removals derived as
  `array_diff($existingGroupIds, $inputData['contact_groups'] ?? [])` at
  `ContactEngine:478`. Omit it, the contact is removed from every group.

The app now always sends all three on edit. A server-side seed for each would
be more robust than relying on every client to know that.

### 2. `contact_groups` matches on `_id`, everything else on `_uid`

`ContactEngine:341` (create) and `:489` (update):

```php
$this->contactGroupRepository->fetchItAll($inputData['contact_groups'], [], '_id')
```

That's `whereIn('_id', …)` — **numeric ids**. But:

- `POST /contacts/{uid}/groups/{groupUid}/remove` takes a **uid**
- the campaign audience (`CampaignApiController:211`) looks up `_uid`
- `/contacts/meta` returns groups with both
- `GET /contacts/{uid}` returns the contact's own groups as `{uid, title}`
  with **no numeric id at all**

Sending uids where ids are expected doesn't error — it matches nothing. On
create that silently assigns no groups. On update it's worse: the removal
`array_diff` sees none of the existing ids in the sent list, so **every group
the contact belongs to is dropped**.

The app hit exactly this. It now carries both identifiers and joins the
contact's groups back to numeric ids through `/contacts/meta`. Adding `id`
alongside `uid` in the contact's own `groups` array would remove the need for
that join; accepting uids in `contact_groups` would remove the problem
entirely and match the rest of the API.

### 3. `contact_tags` validated as `string`, engine accepts `array`

`ContactApiController:173` / `:203` validate
`contact_tags => nullable|string|max:500`, but `syncContactTags()` is typed
`string|array|null` and handles both. An array 422s at validation before the
code that would have accepted it ever runs. Harmless once known — worth
aligning one way or the other.

### 4. Required custom fields are not enforced anywhere

`store()` and `processContactUpdate()` forward `custom_input_fields` without
checking the `required` flag that `/contacts/meta` advertises. This workspace
marks two fields required (Gender, age). A contact created via the API without
them is accepted.

Not necessarily wrong — but it means "required" is advisory, and every client
has to enforce it independently or the columns quietly rot. Worth deciding
deliberately.

### 5. Create's response is not detailed

`ContactApiController:188` returns `$this->shape($created)` — without
`$detailed`. So the object handed back from `POST /contacts` never carries
`city`, `groups` or `customFields`, even for values that were just sent in
that same request. Clients have to re-`GET` to see what they wrote. Passing
`true` there would make the create response self-describing.

### 6. Quality-review rows have no agent identifier

`ReportApiController::stripInternalIds()` says it drops `user_id` because
`user_uid` "already identifies the same agent". For `/reports/agent-targets`
that's true. For `/reports/quality-reviews` it isn't —
`AgentQualityReviewEngine::qualityReport()` never selects a `_uid`, so
stripping `user_id` leaves rows identified only by display name. Same for
`/reports/pause-reasons`, whose rows carry no identifier at all.

Consequence: those two reports cannot link a row to an agent profile.

### 7. Contact search returned nothing for a contact that existed

Lower confidence — I did not chase this. `GET /contacts?q=…` returned no rows
for both a last-name fragment (`FormCheck`) and a phone fragment (`5550199`)
while the contact was present in the unfiltered list. Worth a look at the
`q` handling in `ContactApiController::index()` (`:45–56`).

---

## What the app does today

- Reads city tolerantly: top-level `city`, `contactCity`, `contact_city`, then
  the `__data` / `_data` blob. Cannot recover a value the API doesn't return.
- Sends city, tags and groups on **every** edit, never partially.
- Carries both group identifiers and sends numeric ids for `contact_groups`.
- Enforces required custom fields on create only.

All covered by `test/contact_create_test.dart`.
