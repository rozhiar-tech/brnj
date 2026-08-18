import { readFileSync } from 'node:fs';
import { after, before, beforeEach, describe, it } from 'node:test';
import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
} from '@firebase/rules-unit-testing';
import {
  addDoc,
  collection,
  collectionGroup,
  deleteDoc,
  doc,
  getDoc,
  getDocs,
  limit,
  orderBy,
  query,
  setDoc,
  where,
} from 'firebase/firestore';

let env;

/// Contexts mirror the three tiers the app actually has. `guest` is an
/// anonymous Firebase user rather than an unauthenticated one, because that is
/// what browsing produces — rules must never assume request.auth is null for a
/// person who hasn't registered.
const guest = () =>
  env.authenticatedContext('guest1', { firebase: { sign_in_provider: 'anonymous' } });
const user = (uid = 'user1') =>
  env.authenticatedContext(uid, { firebase: { sign_in_provider: 'phone' } });
const verified = (uid = 'star1') =>
  env.authenticatedContext(uid, {
    verified: true,
    firebase: { sign_in_provider: 'phone' },
  });

before(async () => {
  env = await initializeTestEnvironment({
    projectId: 'brnj-test',
    firestore: {
      rules: readFileSync('../firestore.rules', 'utf8'),
      host: '127.0.0.1',
      port: 8080,
    },
  });
});

after(() => env?.cleanup());
beforeEach(() => env.clearFirestore());

const authorStub = (uid, isVerified = false) => ({
  uid,
  name: 'Cook',
  verified: isVerified,
});

const plan = (uid, isVerified = false) => ({
  owner: authorStub(uid, isVerified),
  weekStart: new Date('2026-08-15'),
  weekEnd: new Date('2026-08-21'),
  visibility: 'private',
  days: Array.from({ length: 7 }, (_, i) => ({ date: new Date(), entries: [] })),
  tags: [],
  dishCount: 0,
});

describe('plans', () => {
  it('lets the owner read their own plan before it exists', async () => {
    // The editor attaches a listener before the first dish is added. A missing
    // document makes `resource` null, so any rule reaching for
    // resource.data errors and the listener fails with permission-denied
    // instead of an empty snapshot. This is the bug that showed a new account
    // nothing but a Retry button.
    const db = user('user1').firestore();
    await assertSucceeds(getDoc(doc(db, 'plans/user1_2026-08-15')));
  });

  it('lets a user with no custom claims create their own plan', async () => {
    // isVerified() used to read request.auth.token.verified directly. Almost
    // nobody carries that claim, and reaching for an absent key errors the
    // whole expression rather than evaluating false.
    const db = user('user1').firestore();
    await assertSucceeds(
      setDoc(doc(db, 'plans/user1_2026-08-15'), plan('user1')),
    );
  });

  it('lets a verified user create a plan claiming verified', async () => {
    const db = verified('star1').firestore();
    await assertSucceeds(
      setDoc(doc(db, 'plans/star1_2026-08-15'), plan('star1', true)),
    );
  });

  it('refuses a plan that claims a verified badge it does not hold', async () => {
    const db = user('user1').firestore();
    await assertFails(
      setDoc(doc(db, 'plans/user1_2026-08-15'), plan('user1', true)),
    );
  });

  it('refuses a plan written under another uid prefix', async () => {
    const db = user('user1').firestore();
    await assertFails(
      setDoc(doc(db, 'plans/user2_2026-08-15'), plan('user1')),
    );
  });

  it('refuses a guest creating a plan', async () => {
    const db = guest().firestore();
    await assertFails(
      setDoc(doc(db, 'plans/guest1_2026-08-15'), plan('guest1')),
    );
  });

  it('hides a private plan from everyone else', async () => {
    await env.withSecurityRulesDisabled(async (admin) => {
      await setDoc(
        doc(admin.firestore(), 'plans/user1_2026-08-15'),
        plan('user1'),
      );
    });
    const db = user('user2').firestore();
    await assertFails(getDoc(doc(db, 'plans/user1_2026-08-15')));
  });

  it('shows a published plan to anyone signed in, guests included', async () => {
    await env.withSecurityRulesDisabled(async (admin) => {
      await setDoc(doc(admin.firestore(), 'plans/user1_2026-08-15'), {
        ...plan('user1'),
        visibility: 'public',
      });
    });
    await assertSucceeds(
      getDoc(doc(guest().firestore(), 'plans/user1_2026-08-15')),
    );
  });

  it('refuses a client writing its own stats', async () => {
    const db = user('user1').firestore();
    await assertFails(
      setDoc(doc(db, 'plans/user1_2026-08-15'), {
        ...plan('user1'),
        stats: { views: 9999, copies: 9999 },
      }),
    );
  });
});

describe('recipes', () => {
  const recipe = (uid, overrides = {}, isVerified = false) => ({
    author: authorStub(uid, isVerified),
    title: 'دولمة',
    language: 'ar',
    status: 'draft',
    ingredients: [{ item: 'رز', unit: 'istikan' }],
    steps: [{ text: 'اغسل الرز' }],
    keywords: [],
    tags: [],
    occasions: [],
    gallery: [],
    ...overrides,
  });

  it('lets a registered user create their own draft', async () => {
    await assertSucceeds(
      setDoc(doc(user('user1').firestore(), 'recipes/r1'), recipe('user1')),
    );
  });

  it('lets the composer create a completely empty draft', async () => {
    // This is the real first write: the composer creates the draft the moment
    // a cover photo is picked, before anything has been typed. The earlier
    // test used a filled-in draft and passed while this flow was denied in the
    // app, which is exactly the gap worth closing.
    await assertSucceeds(
      setDoc(
        doc(user('user1').firestore(), 'recipes/r1'),
        recipe('user1', { title: '', ingredients: [], steps: [] }),
      ),
    );
  });

  it('lets an empty draft be filled in one field at a time', async () => {
    const db = user('user1').firestore();
    await setDoc(
      doc(db, 'recipes/r1'),
      recipe('user1', { title: '', ingredients: [], steps: [] }),
    );
    // Autosave writes after every keystroke-ish change; a half-typed title is
    // a normal intermediate state, not an error.
    await assertSucceeds(
      setDoc(doc(db, 'recipes/r1'), recipe('user1', { title: 'دو' })),
    );
  });

  it('refuses publishing without a title', async () => {
    await assertFails(
      setDoc(
        doc(user('user1').firestore(), 'recipes/r1'),
        recipe('user1', { title: '', status: 'published' }),
      ),
    );
  });

  it('refuses publishing with no steps', async () => {
    await assertFails(
      setDoc(
        doc(user('user1').firestore(), 'recipes/r1'),
        recipe('user1', { steps: [], status: 'published' }),
      ),
    );
  });

  it('allows publishing a complete recipe', async () => {
    await assertSucceeds(
      setDoc(
        doc(user('user1').firestore(), 'recipes/r1'),
        recipe('user1', { status: 'published' }),
      ),
    );
  });

  it('refuses a guest creating a recipe', async () => {
    await assertFails(
      setDoc(doc(guest().firestore(), 'recipes/r1'), recipe('guest1')),
    );
  });

  it('refuses a recipe attributed to someone else', async () => {
    await assertFails(
      setDoc(doc(user('user1').firestore(), 'recipes/r1'), recipe('user2')),
    );
  });

  it('refuses a client setting its own score', async () => {
    await assertFails(
      setDoc(doc(user('user1').firestore(), 'recipes/r1'), {
        ...recipe('user1'),
        score: 9999,
      }),
    );
  });

  it('refuses a title past the length ceiling', async () => {
    await assertFails(
      setDoc(
        doc(user('user1').firestore(), 'recipes/r1'),
        recipe('user1', { title: 'ا'.repeat(121) }),
      ),
    );
  });

  it('hides another author\'s draft', async () => {
    await env.withSecurityRulesDisabled(async (admin) => {
      await setDoc(doc(admin.firestore(), 'recipes/r1'), recipe('user1'));
    });
    await assertFails(getDoc(doc(user('user2').firestore(), 'recipes/r1')));
  });

  it('shows a published recipe to a guest', async () => {
    await env.withSecurityRulesDisabled(async (admin) => {
      await setDoc(doc(admin.firestore(), 'recipes/r1'), {
        ...recipe('user1'),
        status: 'published',
      });
    });
    await assertSucceeds(getDoc(doc(guest().firestore(), 'recipes/r1')));
  });

  it('lets anyone signed in LIST published recipes', async () => {
    // The feed is a query, not a get, and Firestore evaluates list rules
    // differently: the query has to be provably safe, not merely return safe
    // documents. A rule that passes for a single get can still refuse a feed.
    await env.withSecurityRulesDisabled(async (admin) => {
      const db = admin.firestore();
      await setDoc(doc(db, 'recipes/pub1'), {
        ...recipe('user9'), status: 'published', score: 1,
      });
      await setDoc(doc(db, 'recipes/draft1'), recipe('user9'));
    });

    const db = guest().firestore();
    const q = query(
      collection(db, 'recipes'),
      where('status', '==', 'published'),
      orderBy('score', 'desc'),
      limit(20),
    );
    const snap = await assertSucceeds(getDocs(q));
    if (snap.size !== 1) throw new Error(`expected 1 published, got ${snap.size}`);
  });

  it('refuses a feed query that would include drafts', async () => {
    const db = guest().firestore();
    await assertFails(getDocs(query(collection(db, 'recipes'), limit(20))));
  });

  it('resolves a missing recipe as absent rather than denied', async () => {
    // A stale share link should land on "not there", not on a permission error
    // the UI cannot distinguish from a real failure.
    await assertSucceeds(getDoc(doc(user().firestore(), 'recipes/gone')));
  });
});

describe('social', () => {
  const stub = (uid, isVerified = false) => authorStub(uid, isVerified);

  it('lets a registered user post their own cooked entry', async () => {
    await assertSucceeds(
      setDoc(doc(user('user1').firestore(), 'recipes/r1/cooked/user1'), {
        author: stub('user1'),
        note: 'came out great',
      }),
    );
  });

  it('refuses a cooked entry under someone else\'s uid', async () => {
    await assertFails(
      setDoc(doc(user('user1').firestore(), 'recipes/r1/cooked/user2'), {
        author: stub('user2'),
      }),
    );
  });

  it('refuses a cooked entry claiming a verified badge it lacks', async () => {
    // The gallery renders this stub directly, so a forged tick would appear
    // next to a name with no lookup to contradict it.
    await assertFails(
      setDoc(doc(user('user1').firestore(), 'recipes/r1/cooked/user1'), {
        author: stub('user1', true),
      }),
    );
  });

  it('lets a verified user write while their token still says otherwise', async () => {
    // A custom claim only reaches a device when its ID token is reissued, so
    // for up to an hour a freshly verified account has verified:true in its
    // profile and false in its token. Requiring the two to match exactly meant
    // that account could not comment, cook, or post at all during the window.
    // Claiming *no* badge must always be allowed.
    await assertSucceeds(
      addDoc(collection(user('user1').firestore(), 'recipes/r1/comments'), {
        author: stub('user1', false),
        text: 'still able to talk',
      }),
    );
  });

  it('still refuses a badge the token does not back', async () => {
    await assertFails(
      addDoc(collection(user('user1').firestore(), 'recipes/r1/comments'), {
        author: stub('user1', true),
        text: 'forged tick',
      }),
    );
  });

  it('lets a genuinely verified user claim the badge', async () => {
    await assertSucceeds(
      addDoc(collection(verified('star1').firestore(), 'recipes/r1/comments'), {
        author: stub('star1', true),
        text: 'real tick',
      }),
    );
  });

  it('lets a registered user comment', async () => {
    await assertSucceeds(
      addDoc(collection(user('user1').firestore(), 'recipes/r1/comments'), {
        author: stub('user1'),
        text: 'شنو نوع الرز؟',
      }),
    );
  });

  it('refuses an empty comment', async () => {
    await assertFails(
      addDoc(collection(user('user1').firestore(), 'recipes/r1/comments'), {
        author: stub('user1'),
        text: '',
      }),
    );
  });

  it('refuses a guest commenting', async () => {
    await assertFails(
      addDoc(collection(guest().firestore(), 'recipes/r1/comments'), {
        author: stub('guest1'),
        text: 'hello',
      }),
    );
  });

  it('lets a user follow someone', async () => {
    await assertSucceeds(
      setDoc(doc(user('user1').firestore(), 'users/user1/following/user2'), {}),
    );
  });

  it('refuses writing a follow edge into someone else\'s account', async () => {
    await assertFails(
      setDoc(doc(user('user1').firestore(), 'users/user2/following/user3'), {}),
    );
  });

  it('refuses adding yourself to another person\'s follower list', async () => {
    // The mirrored edge is the Function's to write; a client that could write
    // it could manufacture followers.
    await assertFails(
      setDoc(doc(user('user1').firestore(), 'users/user2/followers/user1'), {}),
    );
  });
});

describe('reports and blocking', () => {
  it('lets a registered user file a report', async () => {
    await assertSucceeds(
      setDoc(doc(user('user1').firestore(), 'reports/r1_user1'), {
        targetType: 'recipe',
        targetId: 'r1',
        reporterId: 'user1',
        reason: 'harassment',
        status: 'open',
      }),
    );
  });

  it('refuses a report filed under someone else\'s name', async () => {
    await assertFails(
      setDoc(doc(user('user1').firestore(), 'reports/r1_user2'), {
        targetType: 'recipe',
        targetId: 'r1',
        reporterId: 'user2',
        reason: 'spam',
        status: 'open',
      }),
    );
  });

  it('keeps reports out of ordinary users\' hands', async () => {
    // A reporter who could read the queue could work out who else reported,
    // and being seen to report is exactly what stops people doing it.
    await env.withSecurityRulesDisabled(async (admin) => {
      await setDoc(doc(admin.firestore(), 'reports/r1_user1'), {
        reporterId: 'user1',
        targetId: 'r1',
        status: 'open',
      });
    });
    await assertFails(getDoc(doc(user('user1').firestore(), 'reports/r1_user1')));
  });

  it('lets a signed-in user read another profile', async () => {
    await env.withSecurityRulesDisabled(async (admin) => {
      await setDoc(doc(admin.firestore(), 'users/user2'), {
        displayName: 'Cook',
        counts: { recipes: 3 },
      });
    });
    await assertSucceeds(getDoc(doc(user('user1').firestore(), 'users/user2')));
  });

  it('lets a guest read a profile', async () => {
    await env.withSecurityRulesDisabled(async (admin) => {
      await setDoc(doc(admin.firestore(), 'users/user2'), { displayName: 'Cook' });
    });
    await assertSucceeds(getDoc(doc(guest().firestore(), 'users/user2')));
  });

  it('resolves a profile that does not exist without erroring', async () => {
    // isBlockedBy() does an exists() lookup on a subcollection of a document
    // that may not be there. If that made the rule error rather than evaluate,
    // every unknown uid would read as permission-denied.
    await assertSucceeds(getDoc(doc(user('user1').firestore(), 'users/nobody')));
  });

  it('lets a signed-in user LIST profiles for people search', async () => {
    // The users read rule calls exists() on a subcollection. That is fine for a
    // single get; for a query Firestore evaluates it per returned document and
    // the rule has to be satisfiable by the query itself.
    await env.withSecurityRulesDisabled(async (admin) => {
      const db = admin.firestore();
      await setDoc(doc(db, 'users/p1'), {
        displayName: 'Rozhyar',
        privacy: { discoverable: true },
      });
    });

    const db = user('user1').firestore();
    const q = query(
      collection(db, 'users'),
      where('privacy.discoverable', '==', true),
      where('displayName', '>=', 'Ro'),
      where('displayName', '<', 'Ro\uf8ff'),
      limit(20),
    );
    await assertSucceeds(getDocs(q));
  });

  it('lets a user block someone', async () => {
    await assertSucceeds(
      setDoc(doc(user('user1').firestore(), 'users/user1/blocked/user2'), {}),
    );
  });

  it('refuses writing a block into someone else\'s account', async () => {
    await assertFails(
      setDoc(doc(user('user1').firestore(), 'users/user2/blocked/user3'), {}),
    );
  });

  it('hides a blocker\'s profile from the blocked user', async () => {
    await env.withSecurityRulesDisabled(async (admin) => {
      await setDoc(doc(admin.firestore(), 'users/user1'), { displayName: 'A' });
      await setDoc(doc(admin.firestore(), 'users/user1/blocked/user2'), {});
    });
    await assertFails(getDoc(doc(user('user2').firestore(), 'users/user1')));
  });
});

/// Every query the app actually issues.
///
/// Firestore evaluates `list` rules differently from `get`: a query has to be
/// provably safe from its own constraints, not merely return safe documents.
/// A rule that passes a single-document test can still refuse the screen that
/// uses it, which is how a denied read reached a real phone with no clue
/// attached. These mirror the client queries one for one.
describe('client queries', () => {
  const seed = async (fn) => env.withSecurityRulesDisabled((a) => fn(a.firestore()));

  it('notifications list', async () => {
    await seed((db) =>
      setDoc(doc(db, 'users/user1/notifications/n1'), { read: false, at: new Date() }),
    );
    await assertSucceeds(
      getDocs(query(
        collection(user('user1').firestore(), 'users/user1/notifications'),
        orderBy('at', 'desc'), limit(50),
      )),
    );
  });

  it('unread notification count', async () => {
    await assertSucceeds(
      getDocs(query(
        collection(user('user1').firestore(), 'users/user1/notifications'),
        where('read', '==', false), limit(50),
      )),
    );
  });

  it('saved recipe ids', async () => {
    await assertSucceeds(
      getDocs(query(
        collection(user('user1').firestore(), 'users/user1/saved'),
        orderBy('at', 'desc'),
      )),
    );
  });

  it('blocked ids', async () => {
    await assertSucceeds(
      getDocs(collection(user('user1').firestore(), 'users/user1/blocked')),
    );
  });

  it('following ids', async () => {
    await assertSucceeds(
      getDocs(collection(user('user1').firestore(), 'users/user1/following')),
    );
  });

  it('comments list', async () => {
    await assertSucceeds(
      getDocs(query(
        collection(guest().firestore(), 'recipes/r1/comments'),
        orderBy('createdAt'), limit(100),
      )),
    );
  });

  it('cooked gallery list', async () => {
    await assertSucceeds(
      getDocs(query(
        collection(guest().firestore(), 'recipes/r1/cooked'),
        orderBy('at', 'desc'), limit(30),
      )),
    );
  });

  it('my recipes including drafts', async () => {
    await assertSucceeds(
      getDocs(query(
        collection(user('user1').firestore(), 'recipes'),
        where('author.uid', '==', 'user1'),
        orderBy('createdAt', 'desc'),
      )),
    );
  });

  it('another author\'s published recipes', async () => {
    await assertSucceeds(
      getDocs(query(
        collection(user('user1').firestore(), 'recipes'),
        where('author.uid', '==', 'user2'),
        where('status', '==', 'published'),
        orderBy('createdAt', 'desc'),
      )),
    );
  });

  it('this week in Iraqi kitchens', async () => {
    await assertSucceeds(
      getDocs(query(
        collection(guest().firestore(), 'plans'),
        where('visibility', '==', 'public'),
        where('weekStart', '==', new Date('2026-08-15')),
        orderBy('stats.copies', 'desc'), limit(20),
      )),
    );
  });

  it('a user plan archive', async () => {
    await assertSucceeds(
      getDocs(query(
        collection(user('user1').firestore(), 'plans'),
        where('owner.uid', '==', 'user1'),
        orderBy('weekStart', 'desc'), limit(12),
      )),
    );
  });

  it('moderation: open reports', async () => {
    const mod = env.authenticatedContext('mod1', {
      moderator: true,
      firebase: { sign_in_provider: 'phone' },
    });
    await assertSucceeds(
      getDocs(query(
        collection(mod.firestore(), 'reports'),
        where('status', '==', 'open'), orderBy('createdAt'),
      )),
    );
  });

  it('moderation: pending verification requests', async () => {
    const mod = env.authenticatedContext('mod1', {
      moderator: true,
      firebase: { sign_in_provider: 'phone' },
    });
    await assertSucceeds(
      getDocs(query(
        collection(mod.firestore(), 'verificationRequests'),
        where('status', '==', 'pending'),
      )),
    );
  });

  it('search by keyword', async () => {
    await assertSucceeds(
      getDocs(query(
        collection(guest().firestore(), 'recipes'),
        where('status', '==', 'published'),
        where('keywords', 'array-contains-any', ['دولمه']),
        orderBy('score', 'desc'), limit(30),
      )),
    );
  });
});

describe('notifications', () => {
  it('refuses a client creating one', async () => {
    await assertFails(
      setDoc(doc(user('user1').firestore(), 'users/user1/notifications/n1'), {
        type: 'like',
        actorUid: 'user2',
        read: false,
      }),
    );
  });

  it('lets the owner mark one read', async () => {
    await env.withSecurityRulesDisabled(async (admin) => {
      await setDoc(doc(admin.firestore(), 'users/user1/notifications/n1'), {
        type: 'like',
        actorUid: 'user2',
        read: false,
      });
    });
    await assertSucceeds(
      setDoc(
        doc(user('user1').firestore(), 'users/user1/notifications/n1'),
        { read: true },
        { merge: true },
      ),
    );
  });

  it('refuses rewriting what the notification says', async () => {
    await env.withSecurityRulesDisabled(async (admin) => {
      await setDoc(doc(admin.firestore(), 'users/user1/notifications/n1'), {
        type: 'like',
        actorUid: 'user2',
        read: false,
      });
    });
    await assertFails(
      setDoc(
        doc(user('user1').firestore(), 'users/user1/notifications/n1'),
        { read: true, actorUid: 'someone-else' },
        { merge: true },
      ),
    );
  });

  it('hides notifications from everyone else', async () => {
    await env.withSecurityRulesDisabled(async (admin) => {
      await setDoc(doc(admin.firestore(), 'users/user1/notifications/n1'), {
        type: 'like',
        actorUid: 'user2',
        read: false,
      });
    });
    await assertFails(
      getDoc(doc(user('user2').firestore(), 'users/user1/notifications/n1')),
    );
  });
});

describe('handles', () => {
  it('lets a user claim a free handle', async () => {
    await assertSucceeds(
      setDoc(doc(user('user1').firestore(), 'handles/rozhyar'), {
        uid: 'user1',
      }),
    );
  });

  it('refuses a handle already taken', async () => {
    await env.withSecurityRulesDisabled(async (admin) => {
      await setDoc(doc(admin.firestore(), 'handles/rozhyar'), { uid: 'user1' });
    });
    // create-if-absent is the entire uniqueness mechanism.
    await assertFails(
      setDoc(doc(user('user2').firestore(), 'handles/rozhyar'), {
        uid: 'user2',
      }),
    );
  });

  it('refuses a handle claimed for someone else', async () => {
    await assertFails(
      setDoc(doc(user('user1').firestore(), 'handles/rozhyar'), {
        uid: 'user2',
      }),
    );
  });

  it('refuses handles outside the allowed shape', async () => {
    await assertFails(
      setDoc(doc(user('user1').firestore(), 'handles/ڕۆژیار'), {
        uid: 'user1',
      }),
    );
    await assertFails(
      setDoc(doc(user('user1').firestore(), 'handles/ab'), { uid: 'user1' }),
    );
  });

  it('lets the owner release their handle', async () => {
    await env.withSecurityRulesDisabled(async (admin) => {
      await setDoc(doc(admin.firestore(), 'handles/rozhyar'), { uid: 'user1' });
    });
    await assertSucceeds(
      deleteDoc(doc(user('user1').firestore(), 'handles/rozhyar')),
    );
  });

  it('refuses releasing someone else\'s handle', async () => {
    await env.withSecurityRulesDisabled(async (admin) => {
      await setDoc(doc(admin.firestore(), 'handles/rozhyar'), { uid: 'user1' });
    });
    await assertFails(
      deleteDoc(doc(user('user2').firestore(), 'handles/rozhyar')),
    );
  });
});

describe('view events', () => {
  it('accepts an append from any signed-in user, guests included', async () => {
    await assertSucceeds(
      setDoc(doc(guest().firestore(), 'viewEvents/e1'), {
        uid: 'guest1',
        targetType: 'recipe',
        targetId: 'r1',
        anonymous: true,
      }),
    );
  });

  it('refuses an event attributed to another user', async () => {
    await assertFails(
      setDoc(doc(user('user1').firestore(), 'viewEvents/e1'), {
        uid: 'user2',
        targetType: 'recipe',
        targetId: 'r1',
      }),
    );
  });

  it('is write-only — nobody reads the queue', async () => {
    await env.withSecurityRulesDisabled(async (admin) => {
      await setDoc(doc(admin.firestore(), 'viewEvents/e1'), {
        uid: 'user1',
        targetType: 'recipe',
        targetId: 'r1',
      });
    });
    await assertFails(getDoc(doc(user('user1').firestore(), 'viewEvents/e1')));
  });
});

describe('communities', () => {
  const seed = async (fn) => env.withSecurityRulesDisabled((a) => fn(a.firestore()));

  const community = (overrides = {}) => ({
    name: 'Baghdad kitchens',
    description: 'Everything from Karrada to Adhamiyah',
    category: 'regional',
    privacy: 'public',
    joinPolicy: 'open',
    rules: [],
    moderators: [],
    createdBy: 'owner1',
    searchName: 'baghdad kitchens',
    memberCount: 0,
    postCount: 0,
    ...overrides,
  });

  /// What the client actually sends when creating one: the counters are absent,
  /// because they are Function-owned and the rules reject a create that carries
  /// them.
  const newCommunity = (overrides = {}) => {
    const { memberCount, postCount, ...rest } = community(overrides);
    return rest;
  };

  /// Seeds a community and its member rows in one go. Membership is a document,
  /// so nearly every rule below needs one to exist first.
  const seedCommunity = async (id, overrides = {}, members = ['owner1']) =>
    seed(async (db) => {
      await setDoc(doc(db, `communities/${id}`), community(overrides));
      for (const uid of members) {
        await setDoc(doc(db, `communities/${id}/members/${uid}`), {
          uid,
          author: authorStub(uid),
          role: uid === (overrides.createdBy ?? 'owner1') ? 'owner' : 'member',
          joinedAt: new Date(),
        });
      }
    });

  describe('the community document', () => {
    it('is readable by a guest — browsing is how someone decides to sign up', async () => {
      await seedCommunity('c1');
      await assertSucceeds(getDoc(doc(guest().firestore(), 'communities/c1')));
    });

    it('lets a registered user create one they own', async () => {
      await assertSucceeds(
        setDoc(
          doc(user('user1').firestore(), 'communities/c1'),
          newCommunity({ createdBy: 'user1' }),
        ),
      );
    });

    it('refuses a community created in someone else’s name', async () => {
      await assertFails(
        setDoc(doc(user('user1').firestore(), 'communities/c1'), {
          name: 'Not mine',
          category: 'other',
          privacy: 'public',
          joinPolicy: 'open',
          rules: [],
          moderators: [],
          createdBy: 'someone-else',
        }),
      );
    });

    it('refuses a community that arrives with its member count pre-filled', async () => {
      await assertFails(
        setDoc(doc(user('user1').firestore(), 'communities/c1'), {
          name: 'Inflated',
          category: 'other',
          privacy: 'public',
          joinPolicy: 'open',
          rules: [],
          moderators: [],
          createdBy: 'user1',
          memberCount: 5000,
        }),
      );
    });

    it('refuses a creator who appoints co-moderators up front', async () => {
      await assertFails(
        setDoc(doc(user('user1').firestore(), 'communities/c1'), {
          name: 'Packed',
          category: 'other',
          privacy: 'public',
          joinPolicy: 'open',
          rules: [],
          moderators: ['friend1', 'friend2'],
          createdBy: 'user1',
        }),
      );
    });

    it('refuses a guest', async () => {
      await assertFails(
        setDoc(
          doc(guest().firestore(), 'communities/c1'),
          newCommunity({ createdBy: 'guest1' }),
        ),
      );
    });

    it('lets a moderator edit the settings', async () => {
      await seedCommunity('c1', { moderators: ['mod1'] }, ['owner1', 'mod1']);
      await assertSucceeds(
        setDoc(
          doc(user('mod1').firestore(), 'communities/c1'),
          { ...community({ moderators: ['mod1'] }), name: 'Renamed' },
          { merge: true },
        ),
      );
    });

    it('refuses a plain member editing the settings', async () => {
      await seedCommunity('c1', {}, ['owner1', 'member1']);
      await assertFails(
        setDoc(
          doc(user('member1').firestore(), 'communities/c1'),
          { name: 'Hijacked' },
          { merge: true },
        ),
      );
    });

    it('refuses a moderator inflating the member count', async () => {
      await seedCommunity('c1', { moderators: ['mod1'] }, ['owner1', 'mod1']);
      await assertFails(
        setDoc(
          doc(user('mod1').firestore(), 'communities/c1'),
          { memberCount: 9999 },
          { merge: true },
        ),
      );
    });

    it('lets the creator delete it', async () => {
      await seedCommunity('c1');
      await assertSucceeds(
        deleteDoc(doc(user('owner1').firestore(), 'communities/c1')),
      );
    });

    it('refuses a moderator deleting the community out from under its owner', async () => {
      await seedCommunity('c1', { moderators: ['mod1'] }, ['owner1', 'mod1']);
      await assertFails(
        deleteDoc(doc(user('mod1').firestore(), 'communities/c1')),
      );
    });
  });

  describe('joining', () => {
    it('lets anyone registered join an open community', async () => {
      await seedCommunity('c1');
      await assertSucceeds(
        setDoc(doc(user('user1').firestore(), 'communities/c1/members/user1'), {
          uid: 'user1',
          author: authorStub('user1'),
          role: 'member',
          joinedAt: new Date(),
        }),
      );
    });

    it('refuses a guest joining', async () => {
      await seedCommunity('c1');
      await assertFails(
        setDoc(doc(guest().firestore(), 'communities/c1/members/guest1'), {
          uid: 'guest1',
          author: authorStub('guest1'),
          role: 'member',
          joinedAt: new Date(),
        }),
      );
    });

    it('refuses joining an approval-gated community directly', async () => {
      await seedCommunity('c1', { joinPolicy: 'approval' });
      await assertFails(
        setDoc(doc(user('user1').firestore(), 'communities/c1/members/user1'), {
          uid: 'user1',
          author: authorStub('user1'),
          role: 'member',
          joinedAt: new Date(),
        }),
      );
    });

    it('refuses adding somebody else as a member', async () => {
      await seedCommunity('c1');
      await assertFails(
        setDoc(doc(user('user1').firestore(), 'communities/c1/members/user2'), {
          uid: 'user2',
          author: authorStub('user2'),
          role: 'member',
          joinedAt: new Date(),
        }),
      );
    });

    it('refuses self-appointment as moderator on the way in', async () => {
      await seedCommunity('c1');
      await assertFails(
        setDoc(doc(user('user1').firestore(), 'communities/c1/members/user1'), {
          uid: 'user1',
          author: authorStub('user1'),
          role: 'moderator',
          joinedAt: new Date(),
        }),
      );
    });

    it('refuses an unverified account claiming the tick on its member row', async () => {
      await seedCommunity('c1');
      await assertFails(
        setDoc(doc(user('user1').firestore(), 'communities/c1/members/user1'), {
          uid: 'user1',
          author: authorStub('user1', true),
          role: 'member',
          joinedAt: new Date(),
        }),
      );
    });

    it('lets the creator write their own owner row before the community exists', async () => {
      // The app writes both in one batch. get() reads committed state, so the
      // community is genuinely absent as far as this rule can see — which is
      // the case that has to be allowed or nobody can create anything.
      await assertSucceeds(
        setDoc(doc(user('user1').firestore(), 'communities/new1/members/user1'), {
          uid: 'user1',
          author: authorStub('user1'),
          role: 'owner',
          joinedAt: new Date(),
        }),
      );
    });

    it('lets a member leave', async () => {
      await seedCommunity('c1', {}, ['owner1', 'member1']);
      await assertSucceeds(
        deleteDoc(doc(user('member1').firestore(), 'communities/c1/members/member1')),
      );
    });

    it('refuses the owner leaving — a community with no owner is stuck', async () => {
      await seedCommunity('c1');
      await assertFails(
        deleteDoc(doc(user('owner1').firestore(), 'communities/c1/members/owner1')),
      );
    });

    it('lets a moderator remove a member', async () => {
      await seedCommunity('c1', { moderators: ['mod1'] }, ['owner1', 'mod1', 'member1']);
      await assertSucceeds(
        deleteDoc(doc(user('mod1').firestore(), 'communities/c1/members/member1')),
      );
    });

    it('refuses a member removing another member', async () => {
      await seedCommunity('c1', {}, ['owner1', 'member1', 'member2']);
      await assertFails(
        deleteDoc(doc(user('member1').firestore(), 'communities/c1/members/member2')),
      );
    });
  });

  describe('the approval queue', () => {
    it('lets someone ask to join an approval-gated community', async () => {
      await seedCommunity('c1', { joinPolicy: 'approval' });
      await assertSucceeds(
        setDoc(doc(user('user1').firestore(), 'communities/c1/requests/user1'), {
          uid: 'user1',
          author: authorStub('user1'),
          requestedAt: new Date(),
        }),
      );
    });

    it('refuses a request to an open community — there is nothing to queue for', async () => {
      await seedCommunity('c1');
      await assertFails(
        setDoc(doc(user('user1').firestore(), 'communities/c1/requests/user1'), {
          uid: 'user1',
          author: authorStub('user1'),
          requestedAt: new Date(),
        }),
      );
    });

    it('lets the asker read their own request — the button says "pending" from it', async () => {
      await seedCommunity('c1', { joinPolicy: 'approval' });
      await seed((db) =>
        setDoc(doc(db, 'communities/c1/requests/user1'), {
          uid: 'user1',
          author: authorStub('user1'),
          requestedAt: new Date(),
        }),
      );
      await assertSucceeds(
        getDoc(doc(user('user1').firestore(), 'communities/c1/requests/user1')),
      );
    });

    it('hides other people’s requests from a plain member', async () => {
      await seedCommunity('c1', { joinPolicy: 'approval' }, ['owner1', 'member1']);
      await seed((db) =>
        setDoc(doc(db, 'communities/c1/requests/user1'), {
          uid: 'user1',
          author: authorStub('user1'),
          requestedAt: new Date(),
        }),
      );
      await assertFails(
        getDoc(doc(user('member1').firestore(), 'communities/c1/requests/user1')),
      );
    });

    it('lets a moderator approve — the member row and the request removal together', async () => {
      await seedCommunity('c1', { joinPolicy: 'approval', moderators: ['mod1'] }, [
        'owner1',
        'mod1',
      ]);
      await seed((db) =>
        setDoc(doc(db, 'communities/c1/requests/user1'), {
          uid: 'user1',
          author: authorStub('user1'),
          requestedAt: new Date(),
        }),
      );
      const db = user('mod1').firestore();
      await assertSucceeds(
        setDoc(doc(db, 'communities/c1/members/user1'), {
          uid: 'user1',
          author: authorStub('user1'),
          role: 'member',
          joinedAt: new Date(),
        }),
      );
      await assertSucceeds(
        deleteDoc(doc(db, 'communities/c1/requests/user1')),
      );
    });

    it('lets the asker withdraw', async () => {
      await seedCommunity('c1', { joinPolicy: 'approval' });
      await seed((db) =>
        setDoc(doc(db, 'communities/c1/requests/user1'), {
          uid: 'user1',
          author: authorStub('user1'),
          requestedAt: new Date(),
        }),
      );
      await assertSucceeds(
        deleteDoc(doc(user('user1').firestore(), 'communities/c1/requests/user1')),
      );
    });
  });

  describe('posts', () => {
    const post = (uid, overrides = {}) => ({
      author: authorStub(uid),
      type: 'text',
      body: 'Made kubba today',
      pinned: false,
      createdAt: new Date(),
      ...overrides,
    });

    it('lets a member post', async () => {
      await seedCommunity('c1', {}, ['owner1', 'member1']);
      await assertSucceeds(
        addDoc(collection(user('member1').firestore(), 'communities/c1/posts'), post('member1')),
      );
    });

    it('refuses a non-member posting in a public community', async () => {
      // Readable by all, writable by members — that difference is the whole
      // reason joining is a thing.
      await seedCommunity('c1');
      await assertFails(
        addDoc(collection(user('user1').firestore(), 'communities/c1/posts'), post('user1')),
      );
    });

    it('refuses a member posting under someone else’s name', async () => {
      await seedCommunity('c1', {}, ['owner1', 'member1']);
      await assertFails(
        addDoc(
          collection(user('member1').firestore(), 'communities/c1/posts'),
          post('member1', { author: authorStub('owner1') }),
        ),
      );
    });

    it('refuses an unverified member claiming the tick', async () => {
      await seedCommunity('c1', {}, ['owner1', 'member1']);
      await assertFails(
        addDoc(
          collection(user('member1').firestore(), 'communities/c1/posts'),
          post('member1', { author: authorStub('member1', true) }),
        ),
      );
    });

    it('refuses a member pinning their own post on the way in', async () => {
      await seedCommunity('c1', {}, ['owner1', 'member1']);
      await assertFails(
        addDoc(
          collection(user('member1').firestore(), 'communities/c1/posts'),
          post('member1', { pinned: true }),
        ),
      );
    });

    it('lets a moderator post something already pinned', async () => {
      await seedCommunity('c1', { moderators: ['mod1'] }, ['owner1', 'mod1']);
      await assertSucceeds(
        addDoc(
          collection(user('mod1').firestore(), 'communities/c1/posts'),
          post('mod1', { pinned: true }),
        ),
      );
    });

    it('lets a guest read a public community’s posts', async () => {
      await seedCommunity('c1');
      await seed((db) => setDoc(doc(db, 'communities/c1/posts/p1'), post('owner1')));
      await assertSucceeds(getDoc(doc(guest().firestore(), 'communities/c1/posts/p1')));
    });

    it('hides a private community’s posts from an outsider', async () => {
      await seedCommunity('c1', { privacy: 'private' });
      await seed((db) => setDoc(doc(db, 'communities/c1/posts/p1'), post('owner1')));
      await assertFails(getDoc(doc(user('user1').firestore(), 'communities/c1/posts/p1')));
    });

    it('shows a private community’s posts to its members', async () => {
      await seedCommunity('c1', { privacy: 'private' }, ['owner1', 'member1']);
      await seed((db) => setDoc(doc(db, 'communities/c1/posts/p1'), post('owner1')));
      await assertSucceeds(
        getDoc(doc(user('member1').firestore(), 'communities/c1/posts/p1')),
      );
    });

    it('lets a moderator pin an existing post', async () => {
      await seedCommunity('c1', { moderators: ['mod1'] }, ['owner1', 'mod1', 'member1']);
      await seed((db) => setDoc(doc(db, 'communities/c1/posts/p1'), post('member1')));
      await assertSucceeds(
        setDoc(
          doc(user('mod1').firestore(), 'communities/c1/posts/p1'),
          { pinned: true },
          { merge: true },
        ),
      );
    });

    it('refuses the author pinning their own post', async () => {
      await seedCommunity('c1', {}, ['owner1', 'member1']);
      await seed((db) => setDoc(doc(db, 'communities/c1/posts/p1'), post('member1')));
      await assertFails(
        setDoc(
          doc(user('member1').firestore(), 'communities/c1/posts/p1'),
          { pinned: true },
          { merge: true },
        ),
      );
    });

    it('refuses a moderator rewriting someone else’s words while pinning', async () => {
      await seedCommunity('c1', { moderators: ['mod1'] }, ['owner1', 'mod1', 'member1']);
      await seed((db) => setDoc(doc(db, 'communities/c1/posts/p1'), post('member1')));
      await assertFails(
        setDoc(
          doc(user('mod1').firestore(), 'communities/c1/posts/p1'),
          { pinned: true, body: 'Words I did not write' },
          { merge: true },
        ),
      );
    });

    it('refuses anyone writing the comment count', async () => {
      await seedCommunity('c1', {}, ['owner1', 'member1']);
      await seed((db) => setDoc(doc(db, 'communities/c1/posts/p1'), post('member1')));
      await assertFails(
        setDoc(
          doc(user('member1').firestore(), 'communities/c1/posts/p1'),
          { commentCount: 500 },
          { merge: true },
        ),
      );
    });

    it('lets the author delete their post', async () => {
      await seedCommunity('c1', {}, ['owner1', 'member1']);
      await seed((db) => setDoc(doc(db, 'communities/c1/posts/p1'), post('member1')));
      await assertSucceeds(
        deleteDoc(doc(user('member1').firestore(), 'communities/c1/posts/p1')),
      );
    });

    it('lets a moderator delete somebody else’s post', async () => {
      await seedCommunity('c1', { moderators: ['mod1'] }, ['owner1', 'mod1', 'member1']);
      await seed((db) => setDoc(doc(db, 'communities/c1/posts/p1'), post('member1')));
      await assertSucceeds(
        deleteDoc(doc(user('mod1').firestore(), 'communities/c1/posts/p1')),
      );
    });

    it('refuses a bystander deleting a post', async () => {
      await seedCommunity('c1', {}, ['owner1', 'member1']);
      await seed((db) => setDoc(doc(db, 'communities/c1/posts/p1'), post('member1')));
      await assertFails(
        deleteDoc(doc(user('user1').firestore(), 'communities/c1/posts/p1')),
      );
    });
  });

  describe('post replies', () => {
    const post = { author: authorStub('member1'), type: 'question', body: 'Why?', pinned: false };

    it('lets a member reply', async () => {
      await seedCommunity('c1', {}, ['owner1', 'member1']);
      await seed((db) => setDoc(doc(db, 'communities/c1/posts/p1'), post));
      await assertSucceeds(
        addDoc(collection(user('member1').firestore(), 'communities/c1/posts/p1/comments'), {
          author: authorStub('member1'),
          text: 'Because the rice needs washing',
          createdAt: new Date(),
        }),
      );
    });

    it('refuses a non-member replying', async () => {
      await seedCommunity('c1', {}, ['owner1', 'member1']);
      await seed((db) => setDoc(doc(db, 'communities/c1/posts/p1'), post));
      await assertFails(
        addDoc(collection(user('user1').firestore(), 'communities/c1/posts/p1/comments'), {
          author: authorStub('user1'),
          text: 'Butting in',
          createdAt: new Date(),
        }),
      );
    });

    it('refuses an empty reply', async () => {
      await seedCommunity('c1', {}, ['owner1', 'member1']);
      await seed((db) => setDoc(doc(db, 'communities/c1/posts/p1'), post));
      await assertFails(
        addDoc(collection(user('member1').firestore(), 'communities/c1/posts/p1/comments'), {
          author: authorStub('member1'),
          text: '',
          createdAt: new Date(),
        }),
      );
    });

    it('lets a moderator delete a reply', async () => {
      await seedCommunity('c1', { moderators: ['mod1'] }, ['owner1', 'mod1', 'member1']);
      await seed(async (db) => {
        await setDoc(doc(db, 'communities/c1/posts/p1'), post);
        await setDoc(doc(db, 'communities/c1/posts/p1/comments/x1'), {
          author: authorStub('member1'),
          text: 'Off topic',
          createdAt: new Date(),
        });
      });
      await assertSucceeds(
        deleteDoc(doc(user('mod1').firestore(), 'communities/c1/posts/p1/comments/x1')),
      );
    });
  });

  describe('the queries the app actually makes', () => {
    it('directory, filtered by category', async () => {
      await seedCommunity('c1');
      await assertSucceeds(
        getDocs(query(
          collection(guest().firestore(), 'communities'),
          where('category', '==', 'regional'),
          orderBy('memberCount', 'desc'),
          limit(40),
        )),
      );
    });

    it('directory, unfiltered', async () => {
      await seedCommunity('c1');
      await assertSucceeds(
        getDocs(query(
          collection(guest().firestore(), 'communities'),
          orderBy('memberCount', 'desc'),
          limit(40),
        )),
      );
    });

    it('name search', async () => {
      await seedCommunity('c1');
      await assertSucceeds(
        getDocs(query(
          collection(guest().firestore(), 'communities'),
          orderBy('searchName'),
          limit(20),
        )),
      );
    });

    it('post feed in a public community, as a guest', async () => {
      await seedCommunity('c1');
      await assertSucceeds(
        getDocs(query(
          collection(guest().firestore(), 'communities/c1/posts'),
          orderBy('createdAt', 'desc'),
          limit(30),
        )),
      );
    });

    it('post feed in a private community, as a member', async () => {
      await seedCommunity('c1', { privacy: 'private' }, ['owner1', 'member1']);
      await assertSucceeds(
        getDocs(query(
          collection(user('member1').firestore(), 'communities/c1/posts'),
          orderBy('createdAt', 'desc'),
          limit(30),
        )),
      );
    });

    it('refuses the post feed in a private community to an outsider', async () => {
      await seedCommunity('c1', { privacy: 'private' });
      await assertFails(
        getDocs(query(
          collection(user('user1').firestore(), 'communities/c1/posts'),
          orderBy('createdAt', 'desc'),
          limit(30),
        )),
      );
    });

    it('pinned posts', async () => {
      await seedCommunity('c1');
      await assertSucceeds(
        getDocs(query(
          collection(guest().firestore(), 'communities/c1/posts'),
          where('pinned', '==', true),
          limit(3),
        )),
      );
    });

    it('member list', async () => {
      await seedCommunity('c1');
      await assertSucceeds(
        getDocs(query(
          collection(guest().firestore(), 'communities/c1/members'),
          orderBy('joinedAt', 'desc'),
          limit(100),
        )),
      );
    });

    it('the approval queue, as a moderator', async () => {
      await seedCommunity('c1', { joinPolicy: 'approval', moderators: ['mod1'] }, [
        'owner1',
        'mod1',
      ]);
      await assertSucceeds(
        getDocs(query(
          collection(user('mod1').firestore(), 'communities/c1/requests'),
          orderBy('requestedAt'),
          limit(100),
        )),
      );
    });

    it('refuses the approval queue to a plain member', async () => {
      await seedCommunity('c1', { joinPolicy: 'approval' }, ['owner1', 'member1']);
      await assertFails(
        getDocs(query(
          collection(user('member1').firestore(), 'communities/c1/requests'),
          orderBy('requestedAt'),
          limit(100),
        )),
      );
    });

    it('my communities — the collection-group query over member rows', async () => {
      // The one that needs the redundant `uid` field on every member document:
      // a collection group cannot be filtered by document id.
      await seedCommunity('c1', {}, ['owner1', 'member1']);
      await assertSucceeds(
        getDocs(query(
          collectionGroup(user('member1').firestore(), 'members'),
          where('uid', '==', 'member1'),
          orderBy('joinedAt', 'desc'),
          limit(50),
        )),
      );
    });

    it('refuses the collection-group query without the uid filter', async () => {
      // The filter is what makes the rule provable. Without it this would list
      // every membership in the app, so it has to be denied — and this is the
      // test that says the rule is a filter requirement rather than a hole.
      await seedCommunity('c1', {}, ['owner1', 'member1']);
      await assertFails(
        getDocs(query(
          collectionGroup(user('member1').firestore(), 'members'),
          orderBy('joinedAt', 'desc'),
          limit(50),
        )),
      );
    });

    it('refuses another user\u2019s memberships through the collection group', async () => {
      await seedCommunity('c1', {}, ['owner1', 'member1']);
      await assertFails(
        getDocs(query(
          collectionGroup(user('user1').firestore(), 'members'),
          where('uid', '==', 'member1'),
          orderBy('joinedAt', 'desc'),
          limit(50),
        )),
      );
    });

    it('refuses a private community\u2019s member list to an outsider', async () => {
      await seedCommunity('c1', { privacy: 'private' }, ['owner1', 'member1']);
      await assertFails(
        getDocs(query(
          collection(user('user1').firestore(), 'communities/c1/members'),
          orderBy('joinedAt', 'desc'),
          limit(100),
        )),
      );
    });

    it('post replies', async () => {
      await seedCommunity('c1');
      await seed((db) =>
        setDoc(doc(db, 'communities/c1/posts/p1'), {
          author: authorStub('owner1'),
          type: 'text',
          body: 'Hello',
          pinned: false,
        }),
      );
      await assertSucceeds(
        getDocs(query(
          collection(guest().firestore(), 'communities/c1/posts/p1/comments'),
          orderBy('createdAt'),
          limit(200),
        )),
      );
    });
  });
});

describe('chats', () => {
  const seed = async (fn) => env.withSecurityRulesDisabled((a) => fn(a.firestore()));

  /// Every DM check reads the recipient's profile, so one has to exist. A
  /// missing profile is its own test further down.
  const seedProfile = async (uid, dmMode = 'everyone') =>
    seed((db) =>
      setDoc(doc(db, `users/${uid}`), {
        displayName: 'Cook',
        privacy: { dmMode, discoverable: true },
      }),
    );

  /// `following/{me}` under *their* document means they follow me — the
  /// direction the `following` DM mode turns on.
  const seedFollows = async (follower, followed) =>
    seed((db) =>
      setDoc(doc(db, `users/${follower}/following/${followed}`), { at: new Date() }),
    );

  const dmId = (a, b) => (a < b ? `${a}_${b}` : `${b}_${a}`);

  const dm = (me, other, overrides = {}) => ({
    kind: 'dm',
    memberIds: [me, other].sort(),
    members: { [me]: authorStub(me), [other]: authorStub(other) },
    acceptedBy: [me],
    admins: [],
    createdBy: me,
    createdAt: new Date(),
    ...overrides,
  });

  const seedChat = async (id, data) =>
    seed((db) => setDoc(doc(db, `chats/${id}`), { ...data, updatedAt: new Date() }));

  describe('starting a DM', () => {
    it('lets anyone message someone whose inbox is open', async () => {
      await seedProfile('user2', 'everyone');
      await assertSucceeds(
        setDoc(
          doc(user('user1').firestore(), `chats/${dmId('user1', 'user2')}`),
          dm('user1', 'user2'),
        ),
      );
    });

    it('refuses someone who takes no messages at all', async () => {
      await seedProfile('user2', 'none');
      await assertFails(
        setDoc(
          doc(user('user1').firestore(), `chats/${dmId('user1', 'user2')}`),
          dm('user1', 'user2'),
        ),
      );
    });

    it('refuses a stranger when the inbox is followers-only', async () => {
      await seedProfile('user2', 'following');
      await assertFails(
        setDoc(
          doc(user('user1').firestore(), `chats/${dmId('user1', 'user2')}`),
          dm('user1', 'user2'),
        ),
      );
    });

    it('allows it once they follow you', async () => {
      // The direction is the point: they follow me, not me them. Anyone can
      // follow anyone, so the reverse would be no gate at all.
      await seedProfile('user2', 'following');
      await seedFollows('user2', 'user1');
      await assertSucceeds(
        setDoc(
          doc(user('user1').firestore(), `chats/${dmId('user1', 'user2')}`),
          dm('user1', 'user2'),
        ),
      );
    });

    it('refuses when the recipient has blocked you', async () => {
      await seedProfile('user2', 'everyone');
      await seed((db) =>
        setDoc(doc(db, 'users/user2/blocked/user1'), { at: new Date() }),
      );
      await assertFails(
        setDoc(
          doc(user('user1').firestore(), `chats/${dmId('user1', 'user2')}`),
          dm('user1', 'user2'),
        ),
      );
    });

    it('refuses a conversation under an id of the sender’s choosing', async () => {
      // Otherwise the gate is a formality: fail it once, then create the same
      // conversation again under a different name.
      await seedProfile('user2', 'everyone');
      await assertFails(
        setDoc(
          doc(user('user1').firestore(), 'chats/whatever-i-like'),
          dm('user1', 'user2'),
        ),
      );
    });

    it('refuses marking the recipient as having accepted', async () => {
      await seedProfile('user2', 'everyone');
      await assertFails(
        setDoc(
          doc(user('user1').firestore(), `chats/${dmId('user1', 'user2')}`),
          dm('user1', 'user2', { acceptedBy: ['user1', 'user2'] }),
        ),
      );
    });

    it('refuses a conversation between two other people', async () => {
      await seedProfile('user3', 'everyone');
      await assertFails(
        setDoc(
          doc(user('user1').firestore(), `chats/${dmId('user2', 'user3')}`),
          dm('user2', 'user3'),
        ),
      );
    });

    it('refuses a chat that arrives with unread counts pre-filled', async () => {
      await seedProfile('user2', 'everyone');
      await assertFails(
        setDoc(
          doc(user('user1').firestore(), `chats/${dmId('user1', 'user2')}`),
          dm('user1', 'user2', { unread: { user2: 99 } }),
        ),
      );
    });

    it('refuses a guest starting one', async () => {
      await seedProfile('user2', 'everyone');
      await assertFails(
        setDoc(
          doc(guest().firestore(), `chats/${dmId('guest1', 'user2')}`),
          dm('guest1', 'user2'),
        ),
      );
    });

    it('refuses messaging an account with no profile document', async () => {
      // Denying is the safe direction: every real account has a profile, so
      // this only ever fires on a deleted one or a made-up uid.
      await assertFails(
        setDoc(
          doc(user('user1').firestore(), `chats/${dmId('user1', 'ghost')}`),
          dm('user1', 'ghost'),
        ),
      );
    });
  });

  describe('reading a conversation', () => {
    it('lets a member read it', async () => {
      await seedChat(dmId('user1', 'user2'), dm('user1', 'user2'));
      await assertSucceeds(
        getDoc(doc(user('user1').firestore(), `chats/${dmId('user1', 'user2')}`)),
      );
    });

    it('refuses a bystander', async () => {
      await seedChat(dmId('user1', 'user2'), dm('user1', 'user2'));
      await assertFails(
        getDoc(doc(user('user3').firestore(), `chats/${dmId('user1', 'user2')}`)),
      );
    });

    it('serves the inbox query', async () => {
      await seedChat(dmId('user1', 'user2'), dm('user1', 'user2'));
      await assertSucceeds(
        getDocs(query(
          collection(user('user1').firestore(), 'chats'),
          where('memberIds', 'array-contains', 'user1'),
          orderBy('updatedAt', 'desc'),
          limit(100),
        )),
      );
    });

    it('refuses an inbox query for somebody else', async () => {
      await seedChat(dmId('user1', 'user2'), dm('user1', 'user2'));
      await assertFails(
        getDocs(query(
          collection(user('user3').firestore(), 'chats'),
          where('memberIds', 'array-contains', 'user1'),
          orderBy('updatedAt', 'desc'),
          limit(100),
        )),
      );
    });
  });

  describe('the unread badge', () => {
    it('lets you clear your own', async () => {
      await seedChat(dmId('user1', 'user2'), {
        ...dm('user1', 'user2'),
        unread: { user1: 3, user2: 0 },
      });
      await assertSucceeds(
        setDoc(
          doc(user('user1').firestore(), `chats/${dmId('user1', 'user2')}`),
          { unread: { user1: 0 } },
          { merge: true },
        ),
      );
    });

    it('refuses clearing somebody else’s', async () => {
      await seedChat(dmId('user1', 'user2'), {
        ...dm('user1', 'user2'),
        unread: { user1: 3, user2: 5 },
      });
      await assertFails(
        setDoc(
          doc(user('user1').firestore(), `chats/${dmId('user1', 'user2')}`),
          { unread: { user2: 0 } },
          { merge: true },
        ),
      );
    });

    it('refuses inventing a count for yourself', async () => {
      // Only zero. A client that can set its own badge to any number is a
      // client that can set anyone's.
      await seedChat(dmId('user1', 'user2'), {
        ...dm('user1', 'user2'),
        unread: { user1: 3, user2: 0 },
      });
      await assertFails(
        setDoc(
          doc(user('user1').firestore(), `chats/${dmId('user1', 'user2')}`),
          { unread: { user1: 99 } },
          { merge: true },
        ),
      );
    });
  });

  describe('the request gate', () => {
    it('lets the recipient accept', async () => {
      await seedChat(dmId('user1', 'user2'), dm('user1', 'user2'));
      await assertSucceeds(
        setDoc(
          doc(user('user2').firestore(), `chats/${dmId('user1', 'user2')}`),
          { acceptedBy: ['user1', 'user2'] },
          { merge: true },
        ),
      );
    });

    it('refuses accepting on somebody else’s behalf', async () => {
      await seedChat(dmId('user1', 'user2'), dm('user1', 'user2'));
      await assertFails(
        setDoc(
          doc(user('user1').firestore(), `chats/${dmId('user1', 'user2')}`),
          { acceptedBy: ['user1', 'user2'] },
          { merge: true },
        ),
      );
    });

    it('lets the recipient decline outright', async () => {
      await seedChat(dmId('user1', 'user2'), dm('user1', 'user2'));
      await assertSucceeds(
        deleteDoc(doc(user('user2').firestore(), `chats/${dmId('user1', 'user2')}`)),
      );
    });

    it('refuses deleting a conversation both sides accepted', async () => {
      // Once it is a real conversation, one party cannot erase it for both.
      await seedChat(dmId('user1', 'user2'), {
        ...dm('user1', 'user2'),
        acceptedBy: ['user1', 'user2'],
      });
      await assertFails(
        deleteDoc(doc(user('user2').firestore(), `chats/${dmId('user1', 'user2')}`)),
      );
    });
  });

  describe('messages', () => {
    const message = (uid, overrides = {}) => ({
      author: authorStub(uid),
      kind: 'text',
      text: 'شلونك',
      at: new Date(),
      ...overrides,
    });

    it('lets a member send', async () => {
      await seedChat(dmId('user1', 'user2'), dm('user1', 'user2'));
      await assertSucceeds(
        addDoc(
          collection(user('user1').firestore(), `chats/${dmId('user1', 'user2')}/messages`),
          message('user1'),
        ),
      );
    });

    it('refuses a bystander sending into a conversation', async () => {
      await seedChat(dmId('user1', 'user2'), dm('user1', 'user2'));
      await assertFails(
        addDoc(
          collection(user('user3').firestore(), `chats/${dmId('user1', 'user2')}/messages`),
          message('user3'),
        ),
      );
    });

    it('refuses a message signed with somebody else’s name', async () => {
      await seedChat(dmId('user1', 'user2'), dm('user1', 'user2'));
      await assertFails(
        addDoc(
          collection(user('user1').firestore(), `chats/${dmId('user1', 'user2')}/messages`),
          message('user1', { author: authorStub('user2') }),
        ),
      );
    });

    it('refuses an unverified sender claiming the tick', async () => {
      await seedChat(dmId('user1', 'user2'), dm('user1', 'user2'));
      await assertFails(
        addDoc(
          collection(user('user1').firestore(), `chats/${dmId('user1', 'user2')}/messages`),
          message('user1', { author: authorStub('user1', true) }),
        ),
      );
    });

    it('refuses a client posing as the system', async () => {
      // System messages announce who joined and who left. A client that can
      // write one can put words in the room's mouth.
      await seedChat(dmId('user1', 'user2'), dm('user1', 'user2'));
      await assertFails(
        addDoc(
          collection(user('user1').firestore(), `chats/${dmId('user1', 'user2')}/messages`),
          message('user1', { kind: 'system', text: 'user2 left' }),
        ),
      );
    });

    it('refuses a bystander reading the messages', async () => {
      await seedChat(dmId('user1', 'user2'), dm('user1', 'user2'));
      await seed((db) =>
        setDoc(doc(db, `chats/${dmId('user1', 'user2')}/messages/m1`), message('user1')),
      );
      await assertFails(
        getDoc(doc(user('user3').firestore(), `chats/${dmId('user1', 'user2')}/messages/m1`)),
      );
    });

    it('serves the message query for a member', async () => {
      await seedChat(dmId('user1', 'user2'), dm('user1', 'user2'));
      await assertSucceeds(
        getDocs(query(
          collection(user('user1').firestore(), `chats/${dmId('user1', 'user2')}/messages`),
          orderBy('at', 'desc'),
          limit(60),
        )),
      );
    });

    it('refuses editing what was said', async () => {
      await seedChat(dmId('user1', 'user2'), dm('user1', 'user2'));
      await seed((db) =>
        setDoc(doc(db, `chats/${dmId('user1', 'user2')}/messages/m1`), message('user1')),
      );
      await assertFails(
        setDoc(
          doc(user('user1').firestore(), `chats/${dmId('user1', 'user2')}/messages/m1`),
          { text: 'something else' },
          { merge: true },
        ),
      );
    });

    it('lets the sender delete their own message', async () => {
      await seedChat(dmId('user1', 'user2'), dm('user1', 'user2'));
      await seed((db) =>
        setDoc(doc(db, `chats/${dmId('user1', 'user2')}/messages/m1`), message('user1')),
      );
      await assertSucceeds(
        deleteDoc(doc(user('user1').firestore(), `chats/${dmId('user1', 'user2')}/messages/m1`)),
      );
    });

    it('refuses deleting the other person’s message in a DM', async () => {
      await seedChat(dmId('user1', 'user2'), dm('user1', 'user2'));
      await seed((db) =>
        setDoc(doc(db, `chats/${dmId('user1', 'user2')}/messages/m1`), message('user2')),
      );
      await assertFails(
        deleteDoc(doc(user('user1').firestore(), `chats/${dmId('user1', 'user2')}/messages/m1`)),
      );
    });
  });

  describe('groups', () => {
    const group = (me, others, overrides = {}) => ({
      kind: 'group',
      memberIds: [me, ...others],
      members: Object.fromEntries([me, ...others].map((u) => [u, authorStub(u)])),
      acceptedBy: [me, ...others],
      admins: [me],
      title: 'طبخات الجمعة',
      createdBy: me,
      createdAt: new Date(),
      ...overrides,
    });

    it('lets someone create a group they run', async () => {
      await assertSucceeds(
        setDoc(doc(user('user1').firestore(), 'chats/g1'), group('user1', ['user2'])),
      );
    });

    it('refuses a group with no name', async () => {
      await assertFails(
        setDoc(
          doc(user('user1').firestore(), 'chats/g1'),
          group('user1', ['user2'], { title: '' }),
        ),
      );
    });

    it('refuses handing the admin seat to someone else at creation', async () => {
      await assertFails(
        setDoc(
          doc(user('user1').firestore(), 'chats/g1'),
          group('user1', ['user2'], { admins: ['user2'] }),
        ),
      );
    });

    it('refuses a group the creator is not in', async () => {
      await assertFails(
        setDoc(
          doc(user('user1').firestore(), 'chats/g1'),
          group('user1', ['user2'], { memberIds: ['user2', 'user3'] }),
        ),
      );
    });

    it('lets an admin rename it and add people', async () => {
      await seedChat('g1', group('user1', ['user2']));
      await assertSucceeds(
        setDoc(
          doc(user('user1').firestore(), 'chats/g1'),
          {
            title: 'طبخات الخميس',
            memberIds: ['user1', 'user2', 'user3'],
            members: {
              user1: authorStub('user1'),
              user2: authorStub('user2'),
              user3: authorStub('user3'),
            },
          },
          { merge: true },
        ),
      );
    });

    it('refuses a plain member adding people', async () => {
      await seedChat('g1', group('user1', ['user2']));
      await assertFails(
        setDoc(
          doc(user('user2').firestore(), 'chats/g1'),
          {
            memberIds: ['user1', 'user2', 'user3'],
            members: {
              user1: authorStub('user1'),
              user2: authorStub('user2'),
              user3: authorStub('user3'),
            },
          },
          { merge: true },
        ),
      );
    });

    it('lets a member leave', async () => {
      await seedChat('g1', group('user1', ['user2']));
      await assertSucceeds(
        setDoc(
          doc(user('user2').firestore(), 'chats/g1'),
          {
            memberIds: ['user1'],
            acceptedBy: ['user1'],
            admins: ['user1'],
            members: { user1: authorStub('user1') },
          },
          { merge: true },
        ),
      );
    });

    it('refuses a member removing somebody else on the way out', async () => {
      await seedChat('g1', group('user1', ['user2', 'user3']));
      await assertFails(
        setDoc(
          doc(user('user2').firestore(), 'chats/g1'),
          {
            memberIds: ['user1'],
            acceptedBy: ['user1'],
            admins: ['user1'],
            members: { user1: authorStub('user1') },
          },
          { merge: true },
        ),
      );
    });

    it('lets an admin delete a group they created', async () => {
      await seedChat('g1', group('user1', ['user2']));
      await assertSucceeds(deleteDoc(doc(user('user1').firestore(), 'chats/g1')));
    });

    it('refuses a member deleting the group', async () => {
      await seedChat('g1', group('user1', ['user2']));
      await assertFails(deleteDoc(doc(user('user2').firestore(), 'chats/g1')));
    });
  });

  describe('community rooms', () => {
    const seedCommunityWith = async (cid, members) =>
      seed(async (db) => {
        await setDoc(doc(db, `communities/${cid}`), {
          name: 'Baghdad kitchens',
          category: 'regional',
          privacy: 'public',
          joinPolicy: 'open',
          rules: [],
          moderators: [],
          createdBy: members[0],
        });
        for (const uid of members) {
          await setDoc(doc(db, `communities/${cid}/members/${uid}`), {
            uid,
            author: authorStub(uid),
            role: uid === members[0] ? 'owner' : 'member',
            joinedAt: new Date(),
          });
        }
      });

    const room = (cid, me) => ({
      kind: 'community',
      memberIds: [me],
      members: { [me]: authorStub(me) },
      acceptedBy: [me],
      admins: [],
      title: 'Baghdad kitchens',
      communityId: cid,
      createdBy: me,
      createdAt: new Date(),
    });

    it('lets a community member open the room', async () => {
      await seedCommunityWith('c1', ['user1']);
      await assertSucceeds(
        setDoc(doc(user('user1').firestore(), 'chats/community_c1'), room('c1', 'user1')),
      );
    });

    it('refuses someone who is not in the community', async () => {
      await seedCommunityWith('c1', ['owner1']);
      await assertFails(
        setDoc(doc(user('user1').firestore(), 'chats/community_c1'), room('c1', 'user1')),
      );
    });

    it('refuses a room whose id does not match its community', async () => {
      await seedCommunityWith('c1', ['user1']);
      await assertFails(
        setDoc(doc(user('user1').firestore(), 'chats/community_other'), room('c1', 'user1')),
      );
    });

    it('lets a second community member join the existing room', async () => {
      await seedCommunityWith('c1', ['owner1', 'user1']);
      await seedChat('community_c1', room('c1', 'owner1'));
      await assertSucceeds(
        setDoc(
          doc(user('user1').firestore(), 'chats/community_c1'),
          {
            memberIds: ['owner1', 'user1'],
            acceptedBy: ['owner1', 'user1'],
            members: { owner1: authorStub('owner1'), user1: authorStub('user1') },
          },
          { merge: true },
        ),
      );
    });

    it('refuses an outsider joining the room', async () => {
      await seedCommunityWith('c1', ['owner1']);
      await seedChat('community_c1', room('c1', 'owner1'));
      await assertFails(
        setDoc(
          doc(user('user1').firestore(), 'chats/community_c1'),
          {
            memberIds: ['owner1', 'user1'],
            acceptedBy: ['owner1', 'user1'],
            members: { owner1: authorStub('owner1'), user1: authorStub('user1') },
          },
          { merge: true },
        ),
      );
    });
  });
});
