/// Route path dùng chung (TODO mục 6). Query chỉ chứa ID/khoảng thời gian, không truyền track trong URL.
abstract final class Routes {
  // Khởi tạo
  static const startup = '/';
  static const onboarding = '/onboarding';
  static const welcome = '/welcome';
  static const login = '/auth/login';
  static const register = '/auth/register';
  static const forgotPassword = '/auth/forgot';
  static const resetPassword = '/auth/reset'; // ?token=
  static const verifyEmail = '/auth/verify'; // ?email=
  static const mergeGuest = '/auth/merge';
  static const setupProfile = '/setup/profile';
  static const setupGoal = '/setup/goal';
  static const setupPermissions = '/setup/permissions';
  static const recovery = '/recovery';

  // Tab Home
  static const home = '/home';
  static const dailySteps = '/home/steps'; // ?date=YYYY-MM-DD
  static const homeGoals = '/home/goals';
  static const notifications = '/home/notifications';
  static String homeActivity(String id) => '/home/activity/$id';

  // Tab Progress
  static const progress = '/progress'; // ?period=week|month|year&kind=steps|running&anchor=YYYY-MM-DD
  static const progressRuns = '/progress/runs'; // ?from=ms&to=ms
  static const records = '/progress/records';
  static const recordsHow = '/progress/records/how';
  static String progressActivity(String id) => '/progress/activity/$id';

  // Tab Run
  static const run = '/run';
  static const runActivity = '/run/activity';
  static const runGoal = '/run/goal';
  static const runWorkout = '/run/workout';
  static const runIntervals = '/run/workout/intervals'; // ?planId=
  static const runAudio = '/run/audio';
  static const runLiveShare = '/run/live-share';

  // Tab History
  static const history = '/history';
  static String historyActivity(String id) => '/history/activity/$id';

  // Tab Profile
  static const profile = '/profile';
  static const editProfile = '/profile/edit';
  static const profileGoals = '/profile/goals';
  static const runSettings = '/profile/run-settings';
  static const reminders = '/profile/reminders';
  static const units = '/profile/units';
  static const dataSources = '/profile/data-sources';
  static const devices = '/profile/data-sources/devices';
  static const privacy = '/profile/privacy';
  static const account = '/profile/account';
  static const help = '/profile/help';
  static const explore = '/profile/explore';
  static const clubs = '/profile/explore/clubs';
  static String club(String id) => '/profile/explore/clubs/$id';
  static const challenges = '/profile/explore/challenges';
  static String challenge(String id) => '/profile/explore/challenges/$id';
  static const routesDiscover = '/profile/explore/routes';
  static String routeDetail(String id) => '/profile/explore/routes/$id';

  // Phiên ghi (toàn màn hình, không bottom tab)
  static const countdown = '/session/countdown';
  static const live = '/session/live';
  static const results = '/session/results';
  static const saveActivity = '/session/save';
  static const saved = '/session/saved'; // ?id=

  // Chi tiết hoạt động con (đẩy lên trên route activity của tab hiện tại)
  static String activityMap(String id) => '/activity/$id/map';
  static String activityEdit(String id) => '/activity/$id/edit';
  static String activityShare(String id) => '/activity/$id/share';
}
