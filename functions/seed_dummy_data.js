// functions/seed_dummy_data.js
// Seeds the admin dashboard with realistic dummy data.
//
// HOW TO RUN:
//   1. Go to Firebase Console → Project Settings → Service Accounts
//   2. Click "Generate new private key" → save as functions/serviceAccountKey.json
//   3. cd functions
//   4. node seed_dummy_data.js
//
// Safe to re-run: uses named doc IDs so it won't duplicate.

const admin = require('firebase-admin');
const serviceAccount = require('./serviceAccountKey.json');

admin.initializeApp({ credential: admin.credential.cert(serviceAccount) });
const db = admin.firestore();

// ─── Helpers ──────────────────────────────────────────────────────────────────

function ts(date) { return admin.firestore.Timestamp.fromDate(date); }

function randomDate(start, end) {
  return new Date(start.getTime() + Math.random() * (end.getTime() - start.getTime()));
}

function randomInt(min, max) {
  return Math.floor(Math.random() * (max - min + 1)) + min;
}

function pick(arr) { return arr[Math.floor(Math.random() * arr.length)]; }

// ─── Parents (30) ─────────────────────────────────────────────────────────────

const PARENTS = [
  { id: 'parent_001', full_name: 'Zulaikha Mohd Zain',      email: 'zulaikha.zain@gmail.com',      account_status: 'active' },
  { id: 'parent_002', full_name: 'Khatirah Abdul Razak',    email: 'khatirah.razak@gmail.com',     account_status: 'active' },
  { id: 'parent_003', full_name: 'Nurul Ain Roslan',        email: 'nurulain.roslan@gmail.com',    account_status: 'active' },
  { id: 'parent_004', full_name: 'Siti Hajar Othman',       email: 'sitihajar.othman@gmail.com',   account_status: 'active' },
  { id: 'parent_005', full_name: 'Farah Diyana Kamarudin',  email: 'farah.diyana@gmail.com',       account_status: 'active' },
  { id: 'parent_006', full_name: 'Aisyah Binti Hamid',      email: 'aisyah.hamid@gmail.com',       account_status: 'suspended' },
  { id: 'parent_007', full_name: 'Nabilah Md Nor',          email: 'nabilah.mdnor@gmail.com',      account_status: 'active' },
  { id: 'parent_008', full_name: 'Syahirah Yusoff',         email: 'syahirah.yusoff@yahoo.com',    account_status: 'active' },
  { id: 'parent_009', full_name: 'Hasnah Ismail',           email: 'hasnah.ismail@gmail.com',      account_status: 'active' },
  { id: 'parent_010', full_name: 'Farhana Aziz',            email: 'farhana.aziz@gmail.com',       account_status: 'active' },
  { id: 'parent_011', full_name: 'Zuhaila Ramli',           email: 'zuhaila.ramli@gmail.com',      account_status: 'active' },
  { id: 'parent_012', full_name: 'Roslinda Baharudin',      email: 'roslinda.baha@gmail.com',      account_status: 'active' },
  { id: 'parent_013', full_name: 'Noraini Hassan',          email: 'noraini.hassan@gmail.com',     account_status: 'active' },
  { id: 'parent_014', full_name: 'Mariam Tajuddin',         email: 'mariam.tajuddin@hotmail.com',  account_status: 'active' },
  { id: 'parent_015', full_name: 'Haziqah Zainal',          email: 'haziqah.zainal@gmail.com',     account_status: 'active' },
  { id: 'parent_016', full_name: 'Suraya Mahmud',           email: 'suraya.mahmud@gmail.com',      account_status: 'suspended' },
  { id: 'parent_017', full_name: 'Aziemah Daud',            email: 'aziemah.daud@gmail.com',       account_status: 'active' },
  { id: 'parent_018', full_name: 'Norzahra Wahid',          email: 'norzahra.wahid@gmail.com',     account_status: 'active' },
  { id: 'parent_019', full_name: 'Syafiqah Mustafa',        email: 'syafiqah.mustafa@gmail.com',   account_status: 'active' },
  { id: 'parent_020', full_name: 'Maisarah Saad',           email: 'maisarah.saad@gmail.com',      account_status: 'active' },
  { id: 'parent_021', full_name: 'Hafizuddin Mansor',       email: 'hafizuddin.mansor@gmail.com',  account_status: 'active' },
  { id: 'parent_022', full_name: 'Syahril Idris',           email: 'syahril.idris@gmail.com',      account_status: 'active' },
  { id: 'parent_023', full_name: 'Zulkifli Nordin',         email: 'zulkifli.nordin@yahoo.com',    account_status: 'active' },
  { id: 'parent_024', full_name: 'Faizal Che Mat',          email: 'faizal.chemat@gmail.com',      account_status: 'active' },
  { id: 'parent_025', full_name: 'Hafiz Ariffin',           email: 'hafiz.ariffin@gmail.com',      account_status: 'active' },
  { id: 'parent_026', full_name: 'Ridhwan Samsudin',        email: 'ridhwan.sam@gmail.com',        account_status: 'active' },
  { id: 'parent_027', full_name: 'Khairul Anwar Talib',     email: 'khairul.talib@gmail.com',      account_status: 'active' },
  { id: 'parent_028', full_name: 'Azrul Hisham Omar',       email: 'azrul.omar@gmail.com',         account_status: 'active' },
  { id: 'parent_029', full_name: 'Fadzillah Rahmat',        email: 'fadzillah.rahmat@gmail.com',   account_status: 'active' },
  { id: 'parent_030', full_name: 'Rashdan Lukman',          email: 'rashdan.lukman@gmail.com',     account_status: 'active' },
];

// ─── Child Devices (15, linked to first 15 parents) ──────────────────────────

const DEVICES = [
  { id: 'device_001', parent_id: 'parent_001', child_name: 'Muhammad Irfan',    age: 12, model: 'Redmi Note 12',      brand: 'Xiaomi',   android: '13' },
  { id: 'device_002', parent_id: 'parent_002', child_name: 'Nur Izzah',         age: 10, model: 'Samsung Galaxy A35', brand: 'Samsung',  android: '14' },
  { id: 'device_003', parent_id: 'parent_003', child_name: 'Adam Harith',       age: 14, model: 'OPPO A78',           brand: 'OPPO',     android: '13' },
  { id: 'device_004', parent_id: 'parent_004', child_name: 'Sofea Adriana',     age: 11, model: 'Vivo Y36',           brand: 'vivo',     android: '13' },
  { id: 'device_005', parent_id: 'parent_005', child_name: 'Haris Danial',      age: 13, model: 'Realme C55',         brand: 'realme',   android: '13' },
  { id: 'device_006', parent_id: 'parent_007', child_name: 'Qistina Humaira',   age: 9,  model: 'Samsung Galaxy A54', brand: 'Samsung',  android: '14' },
  { id: 'device_007', parent_id: 'parent_008', child_name: 'Luqmanul Hakim',    age: 15, model: 'Redmi 12C',          brand: 'Xiaomi',   android: '13' },
  { id: 'device_008', parent_id: 'parent_009', child_name: 'Fatimah Azzahra',   age: 12, model: 'OPPO Reno8',         brand: 'OPPO',     android: '12' },
  { id: 'device_009', parent_id: 'parent_010', child_name: 'Aiman Zikri',       age: 11, model: 'Samsung Galaxy A25', brand: 'Samsung',  android: '14' },
  { id: 'device_010', parent_id: 'parent_011', child_name: 'Nur Sabrina',       age: 14, model: 'Infinix Hot 40',     brand: 'Infinix',  android: '13' },
  { id: 'device_011', parent_id: 'parent_012', child_name: 'Danish Rayyan',     age: 10, model: 'Redmi Note 13',      brand: 'Xiaomi',   android: '14' },
  { id: 'device_012', parent_id: 'parent_013', child_name: 'Iman Syahirah',     age: 13, model: 'Vivo V29e',          brand: 'vivo',     android: '14' },
  { id: 'device_013', parent_id: 'parent_014', child_name: 'Harith Faris',      age: 12, model: 'Samsung Galaxy A15', brand: 'Samsung',  android: '14' },
  { id: 'device_014', parent_id: 'parent_015', child_name: 'Khadeeja Maryam',   age: 11, model: 'OPPO A58',           brand: 'OPPO',     android: '13' },
  { id: 'device_015', parent_id: 'parent_021', child_name: 'Zafran Hakimi',     age: 14, model: 'Realme narzo 60',    brand: 'realme',   android: '13' },
];

// ─── Incident templates ───────────────────────────────────────────────────────

const INCIDENT_APPS = [
  'com.whatsapp', 'com.instagram.android', 'com.android.chrome',
  'org.telegram.messenger', 'com.ss.android.ugc.trill', 'com.discord',
];
const INCIDENT_SUMMARIES = [
  'Toxic content in WhatsApp',
  'Cyberbullying detected in Instagram',
  'Harmful language in Telegram',
  'Offensive content in TikTok',
  'Toxic language in Chrome browser',
  'Inappropriate content in Discord',
];
const DETECTORS = ['hybrid_v3_local_lr', 'hybrid_v3_gemini'];

// ─── Incident counts per day (May 31 – Jun 11, 2026) ─────────────────────────

const INCIDENT_SCHEDULE = [
  { date: new Date('2026-05-31'), incidents: 5, bypass: 3 },
  { date: new Date('2026-06-01'), incidents: 8, bypass: 4 },
  { date: new Date('2026-06-02'), incidents: 6, bypass: 2 },
  { date: new Date('2026-06-03'), incidents: 3, bypass: 5 },
  { date: new Date('2026-06-04'), incidents: 7, bypass: 3 },
  { date: new Date('2026-06-05'), incidents: 9, bypass: 4 },
  { date: new Date('2026-06-06'), incidents: 4, bypass: 2 },
  { date: new Date('2026-06-07'), incidents: 6, bypass: 3 },
  { date: new Date('2026-06-08'), incidents: 5, bypass: 4 },
  { date: new Date('2026-06-09'), incidents: 8, bypass: 2 },
  { date: new Date('2026-06-10'), incidents: 4, bypass: 3 },
  { date: new Date('2026-06-11'), incidents: 3, bypass: 1 },
];

// ─── Seeding Functions ────────────────────────────────────────────────────────

async function seedParents() {
  console.log('Seeding parents...');
  const batch = db.batch();
  const regStart = new Date('2025-01-15');
  const regEnd   = new Date('2026-05-01');

  for (const p of PARENTS) {
    const ref = db.collection('parents').doc(p.id);
    batch.set(ref, {
      email:          p.email,
      full_name:      p.full_name,
      date_created:   ts(randomDate(regStart, regEnd)),
      is_active:      p.account_status === 'active',
      account_status: p.account_status,
    }, { merge: true });
  }
  await batch.commit();
  console.log(`  ✓ ${PARENTS.length} parents seeded`);
}

async function seedDevicesAndLinks() {
  console.log('Seeding child devices and parent-child links...');
  const batch = db.batch();
  const linkStart = new Date('2025-03-01');
  const linkEnd   = new Date('2026-05-20');

  for (let i = 0; i < DEVICES.length; i++) {
    const d        = DEVICES[i];
    const linkedAt = randomDate(linkStart, linkEnd);
    const fakeFcm  = `fFakeFCMtoken_device_${String(i + 1).padStart(3, '0')}_abcdefghijklmnop`;

    // child_devices doc
    const devRef = db.collection('child_devices').doc(d.id);
    batch.set(devRef, {
      device_name:      d.model,
      full_name:        d.child_name,
      age:              d.age,
      date_created:     ts(linkedAt),
      setup_complete:   true,
      device_model:     d.model,
      manufacturer:     d.brand,
      android_version:  d.android,
      last_sync:        ts(randomDate(new Date('2026-06-01'), new Date('2026-06-06'))),
      registration_token: fakeFcm,
      permission_status: {
        notifications:  true,
        overlay:        true,
        usage_access:   true,
        accessibility:  true,
        device_admin:   true,
        last_updated:   ts(linkedAt),
      },
    }, { merge: true });

    // parent_child_links doc
    const linkRef = db.collection('parent_child_links').doc(`link_${String(i + 1).padStart(3, '0')}`);
    batch.set(linkRef, {
      parent_id:          d.parent_id,
      device_id:          d.id,
      pairing_code:       String(100000 + i + 1),
      pairing_status:     'linked',
      link_status:        'active',
      linked_at:          ts(linkedAt),
      registration_token: fakeFcm,
    }, { merge: true });
  }
  await batch.commit();
  console.log(`  ✓ ${DEVICES.length} devices and links seeded`);
}

async function seedIncidents() {
  console.log('Seeding incidents...');
  const deviceIds = DEVICES.map(d => d.id);
  let totalSeeded = 0;

  for (const schedule of INCIDENT_SCHEDULE) {
    const batch = db.batch();
    const dayStr = schedule.date.toISOString().slice(0, 10).replace(/-/g, '');

    for (let i = 0; i < schedule.incidents; i++) {
      const hourMin  = new Date(schedule.date);
      hourMin.setHours(randomInt(7, 22), randomInt(0, 59), randomInt(0, 59));

      const app       = pick(INCIDENT_APPS);
      const summary   = pick(INCIDENT_SUMMARIES);
      const detector  = pick(DETECTORS);
      const conf      = parseFloat((Math.random() * 0.24 + 0.75).toFixed(2)); // 0.75–0.99
      const isAlert   = conf >= 0.80;
      const deviceId  = pick(deviceIds);

      const ref = db.collection('incidents').doc(`inc_${dayStr}_${String(i + 1).padStart(2, '0')}`);
      batch.set(ref, {
        device_id:        deviceId,
        text_summary:     summary,
        description:      `Detected via ${detector.includes('gemini') ? 'Gemini AI' : 'local classifier'}`,
        source:           app,
        confidence_score: conf,
        category:         'toxic',
        detected_at:      ts(hourMin),
        is_alert_send:    isAlert,
        is_reviewed:      Math.random() > 0.4,
        detector:         detector,
      }, { merge: true });
    }
    await batch.commit();
    totalSeeded += schedule.incidents;
  }
  console.log(`  ✓ ${totalSeeded} incidents seeded`);
}

async function seedBypassEvents() {
  console.log('Seeding bypass events...');
  const deviceIds = DEVICES.map(d => d.id);
  let totalSeeded = 0;

  for (const schedule of INCIDENT_SCHEDULE) {
    if (schedule.bypass === 0) continue;
    const batch = db.batch();
    const dayStr = schedule.date.toISOString().slice(0, 10).replace(/-/g, '');

    for (let i = 0; i < schedule.bypass; i++) {
      const hourMin = new Date(schedule.date);
      hourMin.setHours(randomInt(8, 21), randomInt(0, 59), randomInt(0, 59));

      const isBlocked = Math.random() > 0.3;
      const deviceId  = pick(deviceIds);

      const ref = db.collection('bypass_events').doc(`byp_${dayStr}_${String(i + 1).padStart(2, '0')}`);
      batch.set(ref, {
        device_id:         deviceId,
        event_type:        'settings_access',
        event_description: isBlocked
          ? 'Child attempted to access SafeChild settings/uninstall.'
          : 'Child opened system settings',
        is_blocked:        isBlocked,
        is_reviewed:       Math.random() > 0.5,
        is_alert_send:     false,
        detected_at:       ts(hourMin),
        timestamp:         ts(hourMin), // admin_service.dart queries by 'timestamp'
      }, { merge: true });
    }
    await batch.commit();
    totalSeeded += schedule.bypass;
  }
  console.log(`  ✓ ${totalSeeded} bypass events seeded`);
}

// ─── Main ─────────────────────────────────────────────────────────────────────

async function main() {
  console.log('\n SafeChild Dummy Data Seeder');
  console.log('══════════════════════════════\n');
  try {
    await seedParents();
    await seedDevicesAndLinks();
    await seedIncidents();
    await seedBypassEvents();
    console.log('\n✅ All done. Reload the admin dashboard.');
  } catch (err) {
    console.error('\n❌ Seed failed:', err.message);
    if (err.message.includes('serviceAccountKey')) {
      console.error('\n→ Download your service account key:');
      console.error('  Firebase Console → Project Settings → Service Accounts → Generate new private key');
      console.error('  Save as: functions/serviceAccountKey.json');
    }
  }
  process.exit(0);
}

main();
