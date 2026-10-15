import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'empty_state.dart';

/// A consistent sign-in invitation for pages that require an account.
class GuestAccountState extends StatelessWidget {
  final IconData icon;
  final String subtitle;
  final String? returnTo;

  const GuestAccountState({
    super.key,
    required this.icon,
    required this.subtitle,
    this.returnTo,
  });

  @override
  Widget build(BuildContext context) => EmptyState(
    icon: icon,
    title: 'Log in to your account',
    subtitle: subtitle,
    subtitleMinLines: 2,
    actionLabel: 'Log In',
    onAction: () => context.push(
      Uri(
        path: '/login',
        queryParameters: returnTo == null ? null : {'redirect': returnTo!},
      ).toString(),
    ),
  );
}
