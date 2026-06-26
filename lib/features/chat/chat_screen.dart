import 'package:flutter_neumorphic_plus/flutter_neumorphic.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:liita/core/theme/app_theme.dart';
import 'package:liita/core/models/chat_message.dart';
import 'package:liita/core/providers/providers.dart';

/// Premium 1-on-1 chat screen with gradient bubbles & glassmorphic input.
class ChatScreen extends ConsumerStatefulWidget {
  final String matchId;
  final String peerName;

  const ChatScreen({super.key, required this.matchId, required this.peerName});

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final _controller = TextEditingController();
  final _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    // Override duty-cycle: continuous scanning while chat is open
    // so messages are received in real time.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(meshServiceProvider).setContinuousMode();
      debugPrint('[ChatScreen] setContinuousMode');
    });
  }

  @override
  void dispose() {
    // Restore foreground duty-cycle when leaving chat
    ref.read(meshServiceProvider).setForegroundMode();
    debugPrint('[ChatScreen] setForegroundMode (chat closed)');
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _sendMessage() {
    final text = _controller.text.trim();
    if (text.isEmpty) return;

    ref.read(appControllerProvider).sendMessage(widget.matchId, text);

    _controller.clear();
    _scrollToBottom();
  }

  void _scrollToBottom() {
    Future.delayed(const Duration(milliseconds: 100), () {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final messagesAsync = ref.watch(messagesProvider(widget.matchId));
    final localProfile = ref.watch(localProfileProvider);

    return Scaffold(
      appBar: AppBar(
        title: Column(
          children: [
            Text(
              widget.peerName,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
            const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.lock_rounded, size: 10, color: AppColors.success),
                SizedBox(width: 4),
                Text(
                  'End-to-end encrypted',
                  style: TextStyle(
                    fontSize: 11,
                    color: AppColors.success,
                    fontWeight: FontWeight.w400,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          // Messages
          Expanded(
            child: messagesAsync.when(
              data: (messages) {
                if (messages.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Neumorphic(
                          style: const NeumorphicStyle(
                            boxShape: NeumorphicBoxShape.circle(),
                            depth: 4,
                            color: NeuDark.base,
                          ),
                          padding: const EdgeInsets.all(18),
                          child: const Icon(
                            Icons.waving_hand_rounded,
                            size: 28,
                            color: NeuDark.accentBright,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.md),
                        Text(
                          'Say hello to ${widget.peerName}!',
                          style: const TextStyle(
                            color: AppColors.textTertiary,
                            fontSize: 15,
                          ),
                        ),
                      ],
                    ),
                  );
                }
                return ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.all(AppSpacing.md),
                  itemCount: messages.length,
                  itemBuilder: (context, i) {
                    final msg = messages[i];
                    final isMine = msg.fromId == localProfile?.deviceId;
                    return _MessageBubble(message: msg, isMine: isMine);
                  },
                );
              },
              loading: () => const Center(
                child: CircularProgressIndicator(color: AppColors.primary),
              ),
              error: (e, _) => Center(child: Text('Error: $e')),
            ),
          ),
          // Input bar
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: AppSpacing.sm,
            ),
            decoration: const BoxDecoration(
              color: NeuDark.base,
              border: Border(
                top: BorderSide(color: NeuDark.hairline, width: 1),
              ),
            ),
            child: SafeArea(
              child: Row(
                children: [
                  Expanded(
                    child: Neumorphic(
                      style: NeumorphicStyle(
                        boxShape: NeumorphicBoxShape.roundRect(
                            BorderRadius.circular(24)),
                        depth: -4,
                        color: NeuDark.base,
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: TextField(
                        controller: _controller,
                        maxLines: null,
                        textInputAction: TextInputAction.send,
                        onSubmitted: (_) => _sendMessage(),
                        style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 15,
                        ),
                        decoration: const InputDecoration(
                          hintText: 'Type a message...',
                          hintStyle: TextStyle(color: AppColors.textTertiary),
                          border: InputBorder.none,
                          contentPadding: EdgeInsets.symmetric(
                            horizontal: AppSpacing.md,
                            vertical: AppSpacing.sm + 2,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  NeumorphicButton(
                    onPressed: _sendMessage,
                    style: const NeumorphicStyle(
                      boxShape: NeumorphicBoxShape.circle(),
                      depth: 3,
                      color: NeuDark.accent,
                    ),
                    padding: const EdgeInsets.all(12),
                    child: const Icon(
                      Icons.send_rounded,
                      color: Colors.white,
                      size: 20,
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

// =============================================================================
// Message bubble — gradient for sent, glassmorphic for received
// =============================================================================

class _MessageBubble extends StatelessWidget {
  final ChatMessage message;
  final bool isMine;

  const _MessageBubble({required this.message, required this.isMine});

  @override
  Widget build(BuildContext context) {
    final time = DateTime.fromMillisecondsSinceEpoch(message.timestamp);
    final timeStr =
        '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Row(
        mainAxisAlignment:
            isMine ? MainAxisAlignment.end : MainAxisAlignment.start,
        children: [
          Container(
            constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width * 0.72,
            ),
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: AppSpacing.sm + 2,
            ),
            decoration: BoxDecoration(
              color: isMine ? AppColors.primary : AppColors.surfaceLight,
              borderRadius: BorderRadius.only(
                topLeft: const Radius.circular(18),
                topRight: const Radius.circular(18),
                bottomLeft: Radius.circular(isMine ? 18 : 4),
                bottomRight: Radius.circular(isMine ? 4 : 18),
              ),
              border: isMine
                  ? null
                  : Border.all(color: NeuDark.hairline, width: 1),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  message.ciphertext,
                  style: TextStyle(
                    color: isMine ? Colors.white : AppColors.textPrimary,
                    fontSize: 15,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      timeStr,
                      style: TextStyle(
                        color: isMine
                            ? Colors.white.withValues(alpha: 0.6)
                            : AppColors.textTertiary,
                        fontSize: 11,
                      ),
                    ),
                    if (isMine) ...[
                      const SizedBox(width: 4),
                      Icon(
                        message.delivered
                            ? Icons.done_all_rounded
                            : Icons.done_rounded,
                        size: 14,
                        color: message.isRead
                            ? Colors.white
                            : Colors.white.withValues(alpha: 0.5),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
