/*
 * SPDX-FileCopyrightText: 2019-2021 Vishesh Handa <me@vhanda.in>
 *
 * SPDX-License-Identifier: AGPL-3.0-or-later
 */

import 'dart:async';

import 'package:badges/badges.dart' as badges;
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:gitjournal/repository.dart';
import 'package:gitjournal/sync_attempt.dart';
import 'package:gitjournal/utils/utils.dart';
import 'package:provider/provider.dart';

class SyncButton extends StatefulWidget {
  @override
  _SyncButtonState createState() => _SyncButtonState();
}

class _SyncButtonState extends State<SyncButton> {
  late StreamSubscription<ConnectivityResult> subscription;
  ConnectivityResult? _connectivity;

  @override
  void initState() {
    super.initState();
    subscription = Connectivity()
        .onConnectivityChanged
        .listen((ConnectivityResult result) {
      setState(() {
        _connectivity = result;
      });
    });
  }

  @override
  void dispose() {
    subscription.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final repo = context.watch<GitJournalRepo>();

    if (_connectivity == ConnectivityResult.none) {
      return GitPendingChangesBadge(
        child: IconButton(
          icon: const Icon(Icons.signal_wifi_off),
          onPressed: () async {
            unawaited(_syncRepo());
          },
        ),
      );
    }
    if (repo.syncStatus == SyncStatus.Pulling) {
      return BlinkingIcon(
        child: GitPendingChangesBadge(
          child: IconButton(
            icon: const Icon(Icons.cloud_download),
            onPressed: () {},
          ),
        ),
      );
    }

    if (repo.syncStatus == SyncStatus.Pushing) {
      return BlinkingIcon(
        child: GitPendingChangesBadge(
          child: IconButton(
            icon: const Icon(Icons.cloud_upload),
            onPressed: () {},
          ),
        ),
      );
    }

    if (repo.syncStatus == SyncStatus.Error) {
      return GitPendingChangesBadge(
        child: IconButton(
          icon: const Icon(Icons.cloud_off),
          onPressed: () async {
            unawaited(_syncRepo());
          },
        ),
      );
    }

    return GitPendingChangesBadge(
      child: IconButton(
        icon: Icon(_syncStatusIcon()),
        onPressed: () async {
          unawaited(_syncRepo());
        },
      ),
    );
  }

  Future<void> _syncRepo() async {
    try {
      final repo = context.read<GitJournalRepo>();
      await repo.syncNotes();
    } on SyncRecoveryFailedException catch (e) {
      final repo = context.read<GitJournalRepo>();
      final branchName = await showDialog<String>(
        context: context,
        builder: (context) => _SyncRecoveryDialog(
          suggestedBranchName: e.suggestedBranchName,
        ),
      );
      if (!mounted || branchName == null) {
        return;
      }

      try {
        final pushedBranch = await repo.pushCurrentStateToNewBranch(branchName);
        if (!mounted) {
          return;
        }

        showSnackbar(
          context,
          'Local notes were safely pushed to "$pushedBranch".',
        );
      } catch (pushError) {
        if (!mounted) {
          return;
        }
        showErrorSnackbar(context, pushError);
      }
    } catch (e) {
      showErrorSnackbar(context, e);
    }
  }

  IconData _syncStatusIcon() {
    final repo = context.watch<GitJournalRepo>();
    switch (repo.syncStatus) {
      case SyncStatus.Error:
        return Icons.cloud_off;

      case SyncStatus.Unknown:
      case SyncStatus.Done:
      default:
        return Icons.cloud_done;
    }
  }
}

class _SyncRecoveryDialog extends StatefulWidget {
  final String suggestedBranchName;

  const _SyncRecoveryDialog({
    required this.suggestedBranchName,
  });

  @override
  State<_SyncRecoveryDialog> createState() => _SyncRecoveryDialogState();
}

class _SyncRecoveryDialogState extends State<_SyncRecoveryDialog> {
  late final TextEditingController _textController;
  final _formKey = GlobalKey<FormState>();

  @override
  void initState() {
    super.initState();
    _textController = TextEditingController(text: widget.suggestedBranchName);
  }

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Sync needs a recovery branch'),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Automatic push recovery did not work. Your local changes are '
              'still safe, and you can push them to a new branch instead.',
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _textController,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Branch name',
              ),
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Please enter a branch name';
                }
                return null;
              },
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () {
            if (_formKey.currentState!.validate()) {
              Navigator.of(context).pop(_textController.text.trim());
            }
          },
          child: const Text('Push branch'),
        ),
      ],
    );
  }
}

class BlinkingIcon extends StatefulWidget {
  final Widget child;
  final int interval;

  const BlinkingIcon({required this.child, this.interval = 500, Key? key});

  @override
  _BlinkingIconState createState() => _BlinkingIconState();
}

class _BlinkingIconState extends State<BlinkingIcon>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      duration: Duration(milliseconds: widget.interval),
      vsync: this,
    );
    _animation = CurvedAnimation(
      parent: _controller,
      curve: Curves.linear,
    );

    _controller.repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _animation,
      child: widget.child,
    );
  }
}

class GitPendingChangesBadge extends StatelessWidget {
  final Widget child;

  const GitPendingChangesBadge({required this.child});

  @override
  Widget build(BuildContext context) {
    var theme = Theme.of(context);
    var darkMode = theme.brightness == Brightness.dark;
    var style = theme.textTheme.bodySmall!.copyWith(
      fontSize: 6.0,
      color: darkMode ? Colors.black : Colors.white,
    );

    final repo = context.watch<GitJournalRepo>();

    return badges.Badge(
      badgeContent: Text(repo.numChanges.toString(), style: style),
      showBadge: repo.numChanges != 0,
      badgeColor: theme.iconTheme.color!,
      position: badges.BadgePosition.topEnd(top: 10.0, end: 4.0),
      child: child,
    );
  }
}
