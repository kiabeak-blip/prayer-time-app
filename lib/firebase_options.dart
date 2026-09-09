class FirebaseConfig {
  static const apiKey = 'AIzaSyBN6EzcK4-De0xBLLocYtLUd_BsacbCzWw';
  static const projectId = 'prayer-times-app-a863d';
  static const _base =
      'https://firestore.googleapis.com/v1/projects/$projectId/databases/(default)/documents';
  static const authUrl =
      'https://identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=$apiKey';
  static String collection(String name) => '$_base/$name';
  static String runQuery() => '$_base:runQuery';

  // HTTP Cloud Functions (us-central1). The Claude API key lives server-side
  // in this function, never in the app binary.
  static const _functionsBase =
      'https://us-central1-$projectId.cloudfunctions.net';
  static String function(String name) => '$_functionsBase/$name';
}
