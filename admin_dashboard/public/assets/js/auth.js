// admin_dashboard/public/assets/js/auth.js - Firebase 이메일/비밀번호 로그인 래퍼(compat SDK).

const isLocalHost = ['localhost', '127.0.0.1'].includes(location.hostname);

export const available = () => !!(window.firebase && window.firebase.auth && window.firebase.firestore);

/** 로컬(에뮬레이터 실행 중)에서만 에뮬레이터로 연결한다. 이미 연결돼 있으면(호스팅 에뮬레이터의 init.js) 그대로 둔다. */
export function connectLocalEmulators() {
  if (!isLocalHost) return;
  try {
    const a = firebase.auth();
    if (!a.emulatorConfig) a.useEmulator('http://127.0.0.1:9099', { disableWarnings: true });
  } catch (e) { /* 이미 사용 중이면 무시 */ }
  try { firebase.firestore().useEmulator('127.0.0.1', 8080); } catch (e) { /* 이미 설정됨 */ }
}

export function watch(cb) { return firebase.auth().onAuthStateChanged(cb); }

export async function signIn(email, password, remember) {
  const auth = firebase.auth();
  await auth.setPersistence(remember ? firebase.auth.Auth.Persistence.LOCAL : firebase.auth.Auth.Persistence.SESSION);
  return auth.signInWithEmailAndPassword(email.trim(), password);
}

export const signOut = () => firebase.auth().signOut();

/** 현재 비밀번호로 재인증한 뒤 새 비밀번호로 바꾼다(Firebase는 민감 작업에 재인증을 요구). */
export async function changePassword(current, next) {
  const user = firebase.auth().currentUser;
  if (!user?.email) throw Object.assign(new Error('not-signed-in'), { code: 'auth/no-current-user' });
  const cred = firebase.auth.EmailAuthProvider.credential(user.email, current);
  await user.reauthenticateWithCredential(cred);
  await user.updatePassword(next);
}

const MESSAGES = {
  'auth/invalid-credential': '이메일 또는 비밀번호가 맞지 않아요.',
  'auth/invalid-login-credentials': '이메일 또는 비밀번호가 맞지 않아요.',
  'auth/wrong-password': '비밀번호가 맞지 않아요.',
  'auth/user-not-found': '등록되지 않은 이메일이에요.',
  'auth/invalid-email': '이메일 형식이 올바르지 않아요.',
  'auth/user-disabled': '사용이 중지된 계정이에요.',
  'auth/too-many-requests': '시도가 너무 많아요. 잠시 뒤에 다시 해 주세요.',
  'auth/network-request-failed': '네트워크 연결을 확인해 주세요.',
  'auth/weak-password': '비밀번호는 6자 이상이어야 해요.',
  'auth/requires-recent-login': '보안을 위해 다시 로그인한 뒤 시도해 주세요.',
  'auth/operation-not-allowed': '이메일 로그인이 켜져 있지 않아요. Firebase 콘솔에서 사용 설정이 필요해요.',
};
export const authMessage = (err) => MESSAGES[err?.code] ?? `문제가 생겼어요. (${err?.code ?? err?.message ?? '알 수 없음'})`;
