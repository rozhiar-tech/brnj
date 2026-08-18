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
