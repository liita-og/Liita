import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:liita/core/theme/app_theme.dart';
import 'package:liita/core/models/broadcast_message.dart';
import 'package:liita/core/providers/providers.dart';
import 'package:liita/core/widgets/avatar_widget.dart';
import 'package:uuid/uuid.dart';

/// The Lounge — flight-wide broadcast chat room with premium glassmorphic UI.
class LoungeScreen extends ConsumerStatefulWidget {
  const LoungeScreen({super.key});

  @override
  ConsumerState<LoungeScreen> createState() => _LoungeScreenState();
}

class _LoungeScreenState extends ConsumerState<LoungeScreen> {
  final _controller = TextEditingController();
  final _scrollController = ScrollController();

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _sendBroadcast() {
    final text = _controller.text.trim();
    if (text.isEmpty) return;

    final localProfile = ref.read(localProfileProvider);
    if (localProfile == null) return;

    final message = BroadcastMessage(
      messageId: const Uuid().v4(),
      fromId: localProfile.deviceId,
      senderName: localProfile.name,
      seatNumber: localProfile.seatNumber,
      text: text,
      timestamp: DateTime.now().millisecondsSinceEpoch,
    );

    ref.read(databaseServiceProvider).insertBroadcast(message);
    _controller.clear();
  }

  @override
  Widget build(BuildContext context) {
    final broadcastsAsync = ref.watch(broadcastsProvider);
    final localProfile = ref.watch(localProfileProvider);
    final peerCount = ref.watch(activePeerCountProvider);

    return Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Lounge'),
            const SizedBox(width: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: AppColors.success.withValues(alpha: 0.10),
                borderRadius: AppRadius.pillAll,
                border: Border.all(
                  color: AppColors.success.withValues(alpha: 0.20),
                  width: 1,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 5,
                    height: 5,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      color: AppColors.success,
                    ),
                  ),
                  const SizedBox(width: 5),
                  Text(
                    peerCount.when(
                      data: (c) => '$c',
                      loading: () => '...',
                      error: (_, __) => '0',
                    ),
                    style: const TextStyle(
                      color: AppColors.success,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          // Public notice banner
          Container(
            width: double.infinity,
            margin: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: AppSpacing.sm,
            ),
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: AppSpacing.sm,
            ),
            decoration: BoxDecoration(
              color: AppColors.surfaceLight,
              borderRadius: AppRadius.mdAll,
              border: Border.all(
                color: AppColors.glassBorder,
                width: 1,
              ),
            ),
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.campaign_rounded, size: 14, color: AppColors.textTertiary),
                SizedBox(width: 6),
                Text(
                  'Messages are visible to all nearby travelers',
                  style: TextStyle(color: AppColors.textTertiary, fontSize: 12),
                ),
              ],
            ),
          ),
          // Messages
          Expanded(
            child: broadcastsAsync.when(
              data: (messages) {
                if (messages.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          width: 64,
                          height: 64,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: AppColors.primary.withValues(alpha: 0.08),
                          ),
                          child: Icon(
                            Icons.forum_outlined,
                            size: 28,
                            color: AppColors.primary.withValues(alpha: 0.4),
                          ),
                        ),
                        const SizedBox(height: AppSpacing.md),
                        const Text(
                          'Be the first to say something!',
                          style: TextStyle(
                            color: AppColors.textTertiary,
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  );
                }
                final reversed = messages.reversed.toList();
                return ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.all(AppSpacing.md),
                  itemCount: reversed.length,
                  itemBuilder: (context, i) {
                    final msg = reversed[i];
                    final isMine = msg.fromId == localProfile?.deviceId;
                    return _BroadcastBubble(message: msg, isMine: isMine);
                  },
                );
              },
              loading: () => const Center(
                child: CircularProgressIndicator(color: AppColors.primary),
              ),
              error: (e, _) => Center(child: Text('Error: $e')),
            ),
          ),
          // Input
          Container(
            padding: const EdgeInsets.all(AppSpacing.sm),
            decoration: const BoxDecoration(
              color: AppColors.surface,
              border: Border(
                top: BorderSide(color: AppColors.glassBorder, width: 1),
              ),
            ),
            child: SafeArea(
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      maxLength: 200,
                      maxLines: null,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _sendBroadcast(),
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 15,
                      ),
                      decoration: InputDecoration(
                        hintText: 'Shout to the cabin...',
                        hintStyle:
                            const TextStyle(color: AppColors.textTertiary),
                        filled: true,
                        fillColor: AppColors.surfaceLight,
                        border: OutlineInputBorder(
                          borderRadius: AppRadius.pillAll,
                          borderSide: const BorderSide(
                            color: AppColors.glassBorder,
                            width: 1,
                          ),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: AppRadius.pillAll,
                          borderSide: const BorderSide(
                            color: AppColors.glassBorder,
                            width: 1,
                          ),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: AppRadius.pillAll,
                          borderSide: const BorderSide(
                            color: AppColors.primary,
                            width: 1,
                          ),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.md,
                          vertical: AppSpacing.sm,
                        ),
                        counterText: '',
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  GestureDetector(
                    onTap: _sendBroadcast,
                    child: Container(
                      width: 44,
                      height: 44,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: AppColors.primaryGradient,
                      ),
                      child: const Icon(
                        Icons.campaign_rounded,
                        color: Colors.white,
                        size: 20,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _BroadcastBubble extends StatelessWidget {
  final BroadcastMessage message;
  final bool isMine;

  const _BroadcastBubble({required this.message, required this.isMine});

  @override
  Widget build(BuildContext context) {
    final time = DateTime.fromMillisecondsSinceEpoch(message.timestamp);
    final timeStr =
        '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!isMine) ...[
            AvatarWidget(name: message.senderName, size: 36),
            const SizedBox(width: AppSpacing.sm),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment:
                  isMine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
              children: [
                if (!isMine)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text(
                      '${message.senderName} · ${message.seatNumber}',
                      style: const TextStyle(
                        color: AppColors.primary,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.md,
                    vertical: AppSpacing.sm,
                  ),
                  decoration: BoxDecoration(
                    gradient: isMine ? AppColors.sentBubbleGradient : null,
                    color: isMine ? null : AppColors.surfaceLight,
                    borderRadius: AppRadius.lgAll,
                    border: isMine
                        ? null
                        : Border.all(
                            color: AppColors.glassBorder,
                            width: 1,
                          ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        message.text,
                        style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 14,
                          height: 1.4,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        timeStr,
                        style: TextStyle(
                          color: isMine
                              ? Colors.white.withValues(alpha: 0.6)
                              : AppColors.textTertiary,
                          fontSize: 10,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (isMine) const SizedBox(width: 44),
        ],
      ),
    );
  }
}
