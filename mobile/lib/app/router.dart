import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/account/account_screen.dart';
import '../features/activity/activity_detail_screen.dart';
import '../features/activity/activity_map_screen.dart';
import '../features/activity/edit_activity_screen.dart';
import '../features/activity/share_activity_screen.dart';
import '../features/auth/forgot_password_screen.dart';
import '../features/auth/login_screen.dart';
import '../features/auth/merge_guest_screen.dart';
import '../features/auth/register_screen.dart';
import '../features/auth/verify_email_screen.dart';
import '../features/auth/welcome_screen.dart';
import '../features/devices/devices_screen.dart';
import '../features/steps/daily_steps_screen.dart';
import '../features/explore/challenges_screen.dart';
import '../features/explore/clubs_screen.dart';
import '../features/explore/explore_screen.dart';
import '../features/explore/routes_screen.dart';
import '../features/goals/goals_screen.dart';
import '../features/history/history_screen.dart';
import '../features/home/home_screen.dart';
import '../features/live/live_share_screen.dart';
import '../features/notifications/notifications_screen.dart';
import '../features/onboarding/onboarding_screen.dart';
import '../features/profile/data_sources_screen.dart';
import '../features/profile/edit_profile_screen.dart';
import '../features/profile/help_screen.dart';
import '../features/profile/privacy_screen.dart';
import '../features/profile/profile_screen.dart';
import '../features/profile/run_settings_screen.dart';
import '../features/profile/units_screen.dart';
import '../features/progress/filtered_runs_screen.dart';
import '../features/progress/progress_screen.dart';
import '../features/progress/records_screen.dart';
import '../features/reminders/reminders_screen.dart';
import '../features/run/activity_selector_screen.dart';
import '../features/run/countdown_screen.dart';
import '../features/run/live_run_screen.dart';
import '../features/run/recovery_screen.dart';
import '../features/run/results_screen.dart';
import '../features/run/run_goal_screen.dart';
import '../features/run/run_prepare_screen.dart';
import '../features/run/save_activity_screen.dart';
import '../features/run/saved_screen.dart';
import '../features/setup/setup_goal_screen.dart';
import '../features/setup/setup_permissions_screen.dart';
import '../features/setup/setup_profile_screen.dart';
import '../features/startup/startup_screen.dart';
import '../features/workout/interval_editor_screen.dart';
import '../features/workout/workout_chooser_screen.dart';
import 'app_shell.dart';
import 'routes.dart';

final rootNavigatorKey = GlobalKey<NavigatorState>(debugLabel: 'root');

GoRoute _activityRoute() => GoRoute(
  path: 'activity/:id',
  builder: (c, s) => ActivityDetailScreen(activityId: s.pathParameters['id']!),
);

/// Router (D03/D04): 5 tab giữ state riêng bằng StatefulShellRoute; màn ghi chạy nằm ngoài shell (không bottom tab).
final routerProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    navigatorKey: rootNavigatorKey,
    initialLocation: Routes.startup,
    routes: [
      GoRoute(path: Routes.startup, builder: (c, s) => const StartupScreen()),
      GoRoute(path: Routes.onboarding, builder: (c, s) => const OnboardingScreen()),
      GoRoute(path: Routes.welcome, builder: (c, s) => const WelcomeScreen()),
      GoRoute(path: Routes.login, builder: (c, s) => const LoginScreen()),
      GoRoute(path: Routes.register, builder: (c, s) => const RegisterScreen()),
      GoRoute(path: Routes.forgotPassword, builder: (c, s) => const ForgotPasswordScreen()),
      GoRoute(
        path: Routes.resetPassword,
        builder: (c, s) => ResetPasswordScreen(token: s.uri.queryParameters['token']),
      ),
      GoRoute(
        path: Routes.verifyEmail,
        builder: (c, s) => VerifyEmailScreen(email: s.uri.queryParameters['email']),
      ),
      GoRoute(path: Routes.mergeGuest, builder: (c, s) => const MergeGuestScreen()),
      GoRoute(path: Routes.setupProfile, builder: (c, s) => const SetupProfileScreen()),
      GoRoute(path: Routes.setupGoal, builder: (c, s) => const SetupGoalScreen()),
      GoRoute(path: Routes.setupPermissions, builder: (c, s) => const SetupPermissionsScreen()),
      GoRoute(path: Routes.recovery, builder: (c, s) => const RecoveryScreen()),

      // Phiên ghi: ẩn bottom navigation.
      GoRoute(path: Routes.countdown, builder: (c, s) => const CountdownScreen()),
      GoRoute(path: Routes.live, builder: (c, s) => const LiveRunScreen()),
      GoRoute(path: Routes.results, builder: (c, s) => const ResultsScreen()),
      GoRoute(path: Routes.saveActivity, builder: (c, s) => const SaveActivityScreen()),
      GoRoute(
        path: Routes.saved,
        builder: (c, s) => SavedScreen(activityId: s.uri.queryParameters['id'] ?? ''),
      ),

      GoRoute(
        path: '/activity/:id/map',
        parentNavigatorKey: rootNavigatorKey,
        builder: (c, s) => ActivityMapScreen(activityId: s.pathParameters['id']!),
      ),
      GoRoute(
        path: '/activity/:id/edit',
        parentNavigatorKey: rootNavigatorKey,
        builder: (c, s) => EditActivityScreen(activityId: s.pathParameters['id']!),
      ),
      GoRoute(
        path: '/activity/:id/share',
        parentNavigatorKey: rootNavigatorKey,
        builder: (c, s) => ShareActivityScreen(activityId: s.pathParameters['id']!),
      ),

      StatefulShellRoute.indexedStack(
        builder: (context, state, shell) => AppShell(shell: shell),
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: Routes.home,
                builder: (c, s) => const HomeScreen(),
                routes: [
                  GoRoute(
                    path: 'steps',
                    builder: (c, s) => DailyStepsScreen(date: s.uri.queryParameters['date']),
                  ),
                  GoRoute(path: 'goals', builder: (c, s) => const GoalsScreen()),
                  GoRoute(path: 'notifications', builder: (c, s) => const NotificationsScreen()),
                  _activityRoute(),
                ],
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: Routes.progress,
                builder: (c, s) =>
                    ProgressScreen(period: s.uri.queryParameters['period'], kind: s.uri.queryParameters['kind'], anchor: s.uri.queryParameters['anchor']),
                routes: [
                  GoRoute(
                    path: 'runs',
                    builder: (c, s) => FilteredRunsScreen(
                      fromMs: int.tryParse(s.uri.queryParameters['from'] ?? ''),
                      toMs: int.tryParse(s.uri.queryParameters['to'] ?? ''),
                      title: s.uri.queryParameters['title'],
                    ),
                  ),
                  GoRoute(
                    path: 'records',
                    builder: (c, s) => const RecordsScreen(),
                    routes: [GoRoute(path: 'how', builder: (c, s) => const RecordsHowScreen())],
                  ),
                  _activityRoute(),
                ],
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: Routes.run,
                builder: (c, s) => const RunPrepareScreen(),
                routes: [
                  GoRoute(path: 'activity', builder: (c, s) => const ActivitySelectorScreen()),
                  GoRoute(path: 'goal', builder: (c, s) => const RunGoalScreen()),
                  GoRoute(path: 'audio', builder: (c, s) => const RunSettingsScreen()),
                  GoRoute(path: 'live-share', builder: (c, s) => const LiveShareScreen()),
                  GoRoute(
                    path: 'workout',
                    builder: (c, s) => const WorkoutChooserScreen(),
                    routes: [
                      GoRoute(
                        path: 'intervals',
                        builder: (c, s) => IntervalEditorScreen(planId: s.uri.queryParameters['planId']),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(path: Routes.history, builder: (c, s) => const HistoryScreen(), routes: [_activityRoute()]),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: Routes.profile,
                builder: (c, s) => const ProfileScreen(),
                routes: [
                  GoRoute(path: 'edit', builder: (c, s) => const EditProfileScreen()),
                  GoRoute(path: 'goals', builder: (c, s) => const GoalsScreen()),
                  GoRoute(path: 'run-settings', builder: (c, s) => const RunSettingsScreen()),
                  GoRoute(path: 'reminders', builder: (c, s) => const RemindersScreen()),
                  GoRoute(path: 'units', builder: (c, s) => const UnitsScreen()),
                  GoRoute(
                    path: 'data-sources',
                    builder: (c, s) => const DataSourcesScreen(),
                    routes: [GoRoute(path: 'devices', builder: (c, s) => const DevicesScreen())],
                  ),
                  GoRoute(path: 'privacy', builder: (c, s) => const PrivacyScreen()),
                  GoRoute(path: 'account', builder: (c, s) => const AccountScreen()),
                  GoRoute(path: 'help', builder: (c, s) => const HelpScreen()),
                  GoRoute(
                    path: 'explore',
                    builder: (c, s) => const ExploreScreen(),
                    routes: [
                      GoRoute(
                        path: 'clubs',
                        builder: (c, s) => const ClubsScreen(),
                        routes: [
                          GoRoute(
                            path: ':id',
                            builder: (c, s) => ClubDetailScreen(clubId: s.pathParameters['id']!),
                          ),
                        ],
                      ),
                      GoRoute(
                        path: 'challenges',
                        builder: (c, s) => const ChallengesScreen(),
                        routes: [
                          GoRoute(
                            path: ':id',
                            builder: (c, s) => ChallengeDetailScreen(challengeId: s.pathParameters['id']!),
                          ),
                        ],
                      ),
                      GoRoute(
                        path: 'routes',
                        builder: (c, s) => const RoutesScreen(),
                        routes: [
                          GoRoute(
                            path: ':id',
                            builder: (c, s) => RouteDetailScreen(routeId: s.pathParameters['id']!),
                          ),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    ],
  );
});
