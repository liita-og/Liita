import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:liita/core/theme/app_theme.dart';
import 'package:liita/core/models/broadcast_message.dart';
import 'package:liita/core/providers/providers.dart';

/// The Lounge — flight-wide broadcast chat.
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
    ref.read(appControllerProvider).sendBroadcast(text, localProfile);
    _controller.clear();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  /// Scroll to the bottom of the list.
  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final broadcastsAsync = ref.watch(broadcastsProvider);
    final localProfile = ref.watch(localProfileProvider);
    final peersAsync = ref.watch(peersProvider);
    final peerCount = peersAsync.whenOrNull(data: (p) => p.length) ?? 0;

    // Auto-scroll to bottom whenever new messages arrive from any source.
    ref.listen<AsyncValue<List<BroadcastMessage>>>(broadcastsProvider,
        (prev, next) {
      final prevLen = prev?.whenOrNull(data: (m) => m.length) ?? 0;
      final nextLen = next.whenOrNull(data: (m) => m.length) ?? 0;
      if (nextLen > prevLen) _scrollToBottom();
    });

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            // ── Header ──────────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Flight Lounge',
                          style: TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 18,
                            fontWeight: FontWeight.w500,
                            letterSpacing: -0.3,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${peerCount + 1} passengers',
                          style: const TextStyle(
                            color: AppColors.textTertiary,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Icon(
                    Icons.signal_wifi_statusbar_4_bar_rounded,
                    color: AppColors.textTertiary,
                    size: 18,
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),
            const Divider(height: 1, thickness: 1, color: AppColors.glassBorder),

            // ── Messages ─────────────────────────────────────────────────────
            Expanded(
              child: broadcastsAsync.when(
                data: (messages) => messages.isEmpty
                    ? const Center(
                        child: Text(
                          'No messages yet.\nSay hello to the flight.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: AppColors.textTertiary,
                            fontSize: 14,
                            height: 1.6,
                          ),
                        ),
                      )
                    : ListView.builder(
                        controller: _scrollController,
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                        itemCount: messages.length,
                        itemBuilder: (context, i) {
                          // Natural order: index 0 = oldest (top), last = newest (bottom)
                          final msg = messages[i];
                          final isMe = msg.fromId == localProfile?.deviceId;
                          return _MessageBubble(message: msg, isMe: isMe);
                        },
                      ),
                loading: () => const SizedBox.shrink(),
                error: (e, _) => Center(
                  child: Text('$e',
                      style: const TextStyle(color: AppColors.error, fontSize: 13)),
                ),
              ),
            ),

            // ── Input bar ────────────────────────────────────────────────────
            Container(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
              color: AppColors.background,
              child: SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Container(
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: AppColors.glassBorder, width: 1),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _controller,
                            style: const TextStyle(
                              color: AppColors.textPrimary,
                              fontSize: 14,
                            ),
                            decoration: const InputDecoration(
                              hintText: 'Message the flight...',
                              hintStyle: TextStyle(color: AppColors.textTertiary),
                              border: InputBorder.none,
                              contentPadding: EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 14,
                              ),
                            ),
                            textCapitalization: TextCapitalization.sentences,
                            onSubmitted: (_) => _sendBroadcast(),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: GestureDetector(
                            onTap: _sendBroadcast,
                            child: Container(
                              width: 32,
                              height: 32,
                              decoration: const BoxDecoration(
                                color: AppColors.primary,
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.arrow_upward_rounded,
                                color: AppColors.textOnPrimary,
                                size: 16,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  final BroadcastMessage message;
  final bool isMe;

  const _MessageBubble({required this.message, required this.isMe});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Row(
        mainAxisAlignment:
            isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
        children: [
          Flexible(
            child: Column(
              crossAxisAlignment:
                  isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
              children: [
                if (!isMe)
                  Padding(
                    padding: const EdgeInsets.only(left: 4, bottom: 4),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          message.senderName,
                          style: const TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          message.seatNumber,
                          style: const TextStyle(
                            color: AppColors.textTertiary,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 10),
                  constraints: BoxConstraints(
                    maxWidth: MediaQuery.of(context).size.width * 0.72,
                  ),
                  decoration: BoxDecoration(
                    color: isMe ? AppColors.primary : AppColors.surface,
                    borderRadius: BorderRadius.only(
                      topLeft: const Radius.circular(16),
                      topRight: const Radius.circular(16),
                      bottomLeft: Radius.circular(isMe ? 16 : 4),
                      bottomRight: Radius.circular(isMe ? 4 : 16),
                    ),
                    border: isMe
                        ? null
                        : Border.all(color: AppColors.glassBorder, width: 1),
                  ),
                  child: Text(
                    message.text,
                    style: TextStyle(
                      color: isMe
                          ? AppColors.textOnPrimary
                          : AppColors.textPrimary,
                      fontSize: 14,
                      height: 1.4,
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(top: 4, left: 4, right: 4),
                  child: Text(
                    _formatTime(message.timestamp),
                    style: const TextStyle(
                      color: AppColors.textTertiary,
                      fontSize: 10,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _formatTime(int epochMs) {
    final dt = DateTime.fromMillisecondsSinceEpoch(epochMs);
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }
}
