import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';

import 'package:liita/core/theme/app_theme.dart';
import 'package:liita/core/providers/providers.dart';
import 'package:liita/core/providers/game_provider.dart';
import 'package:liita/core/models/game_message.dart';

class TriviaScreen extends ConsumerStatefulWidget {
  const TriviaScreen({super.key});

  @override
  ConsumerState<TriviaScreen> createState() => _TriviaScreenState();
}

class _TriviaScreenState extends ConsumerState<TriviaScreen>
    with SingleTickerProviderStateMixin {

  static const int _questionSeconds = 15;
  static const int _absoluteTimeoutSeconds = 20;

  // Question countdown
  Timer? _questionTimer;
  Timer? _absoluteTimer;
  int _secondsLeft = _questionSeconds;
  bool _timerExpiredHandled = false;

  // Result auto-advance
  Timer? _resultTimer;

  // Which option the player tapped (for visual feedback)
  int? _tappedIndex;

  late AnimationController _timerAnim;

  @override
  void initState() {
    super.initState();
    _timerAnim = AnimationController(
      vsync: this,
      duration: const Duration(seconds: _questionSeconds),
    );
  }

  @override
  void dispose() {
    _questionTimer?.cancel();
    _absoluteTimer?.cancel();
    _resultTimer?.cancel();
    _timerAnim.dispose();
    super.dispose();
  }

  // ── Timer control ──────────────────────────────────────────────────────────

  void _startQuestionTimer() {
    _questionTimer?.cancel();
    _absoluteTimer?.cancel();
    _timerExpiredHandled = false;
    _tappedIndex = null;

    setState(() => _secondsLeft = _questionSeconds);
    _timerAnim.forward(from: 0.0);

    _questionTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) { t.cancel(); return; }
      setState(() => _secondsLeft--);
      if (_secondsLeft <= 0) {
        t.cancel();
        _onTimerExpired();
      }
    });

    // HOST absolute timeout: 20s total (15s + 5s grace for opponent packet)
    final state = ref.read(triviaGameProvider);
    if (state?.isHost == true) {
      _absoluteTimer = Timer(
          const Duration(seconds: _absoluteTimeoutSeconds), _onAbsoluteTimeout);
    }
  }

  void _stopTimers() {
    _questionTimer?.cancel();
    _absoluteTimer?.cancel();
    _timerAnim.stop();
  }

  void _onTimerExpired() {
    if (_timerExpiredHandled) return;
    _timerExpiredHandled = true;
    _stopTimers();
    final answerToSend = ref.read(triviaGameProvider.notifier).onTimerExpired();
    if (answerToSend != null) _sendAnswerPacket(answerToSend);
  }

  void _onAbsoluteTimeout() {
    final state = ref.read(triviaGameProvider);
    if (state == null || !state.isHost) return;
    final resultPayload =
        ref.read(triviaGameProvider.notifier).forceOpponentTimeout();
    if (resultPayload != null) {
      _sendResultPacket(resultPayload);
      _startResultTimer();
    }
  }

  void _startResultTimer() {
    _resultTimer?.cancel();
    _resultTimer = Timer(const Duration(milliseconds: 2000), _onResultTimerDone);
  }

  void _onResultTimerDone() {
    final state = ref.read(triviaGameProvider);
    if (state == null || !mounted) return;

    if (state.isHost) {
      final nextQuestion =
          ref.read(triviaGameProvider.notifier).advanceToNextQuestion();
      if (nextQuestion != null) {
        _sendQuestionPacket(nextQuestion, state.currentQuestionIndex + 1);
        _startQuestionTimer();
      } else {
        // Game over — send end packet
        _sendEndPacket();
      }
    } else {
      ref.read(triviaGameProvider.notifier).acknowledgeResult();
      // Wait for next question packet from host
    }
  }

  // ── Packet senders (UI→mesh) ───────────────────────────────────────────────

  void _sendAnswerPacket(int answerIndex) {
    final state = ref.read(triviaGameProvider);
    if (state == null) return;
    ref.read(appControllerProvider).sendGameMessage(
      state.opponentId,
      GameMessage(
        gameId: state.gameId,
        gameType: GameType.trivia,
        type: GameMessageType.answer,
        payload: {
          'selectedIndex': answerIndex,
          'questionIndex': state.currentQuestionIndex,
        },
      ),
    );
  }

  void _sendQuestionPacket(Map<String, dynamic> question, int index) {
    final state = ref.read(triviaGameProvider);
    if (state == null) return;
    ref.read(appControllerProvider).sendGameMessage(
      state.opponentId,
      GameMessage(
        gameId: state.gameId,
        gameType: GameType.trivia,
        type: GameMessageType.question,
        payload: {'question': question, 'index': index},
      ),
    );
  }

  void _sendResultPacket(Map<String, dynamic> resultPayload) {
    final state = ref.read(triviaGameProvider);
    if (state == null) return;
    ref.read(appControllerProvider).sendGameMessage(
      state.opponentId,
      GameMessage(
        gameId: state.gameId,
        gameType: GameType.trivia,
        type: GameMessageType.result,
        payload: resultPayload,
      ),
    );
  }

  void _sendEndPacket() {
    final state = ref.read(triviaGameProvider);
    if (state == null) return;
    ref.read(appControllerProvider).sendGameMessage(
      state.opponentId,
      GameMessage(
        gameId: state.gameId,
        gameType: GameType.trivia,
        type: GameMessageType.end,
        payload: {
          'hostScore': state.myScore,
          'opponentScore': state.opponentScore,
        },
      ),
    );
  }

  // ── User taps an answer ────────────────────────────────────────────────────

  void _onAnswerTapped(int index) {
    _stopTimers();
    setState(() => _tappedIndex = index);
    final answerToSend =
        ref.read(triviaGameProvider.notifier).submitAnswer(index);
    if (answerToSend != null) {
      // Opponent: send to host
      _sendAnswerPacket(answerToSend);
    }
    // Host: wait for result via AppController._handleTrivia → onAnswerReceived
    // If host and both answers in, AppController already sent result; we just
    // need to watch for phase change to showingResult.
  }

  // ── Watch phase changes ────────────────────────────────────────────────────

  TriviaPhase? _lastPhase;

  void _onPhaseChange(TriviaGameState? state) {
    if (state == null) return;
    if (state.phase == _lastPhase) return;
    _lastPhase = state.phase;

    switch (state.phase) {
      case TriviaPhase.answering:
        _startQuestionTimer();
        break;
      case TriviaPhase.showingResult:
        _stopTimers();
        // HOST: result already sent by AppController; start display timer.
        // OPPONENT: result arrived; start display timer.
        _startResultTimer();
        break;
      case TriviaPhase.waitingForQuestion:
      case TriviaPhase.waitingForOpponent:
      case TriviaPhase.waitingForResult:
        _stopTimers();
        break;
      case TriviaPhase.finished:
        _stopTimers();
        break;
      case TriviaPhase.waitingForAccept:
        break;
    }
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(triviaGameProvider);

    // React to phase changes for timers
    ref.listen<TriviaGameState?>(triviaGameProvider, (_, next) {
      _onPhaseChange(next);
    });

    // Also: if host receives result payload back from AppController
    // (opponentAnswer in, both scored), we need to show result and send it.
    // This is handled by AppController directly setting state via notifier,
    // so the ref.listen above catches the phase → showingResult transition.
    // However, we also need to send the result packet if AppController
    // returned a payload. This is already done in AppController._handleTrivia
    // for the 'answer' case. Nothing extra needed here.

    if (state == null) {
      return Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          backgroundColor: AppColors.background,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back, color: AppColors.textPrimary),
            onPressed: () {
              ref.read(triviaGameProvider.notifier).reset();
              context.pop();
            },
          ),
        ),
        body: const Center(
          child: Text('Game not found',
              style: TextStyle(color: AppColors.textSecondary)),
        ),
      );
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        automaticallyImplyLeading: false,
        centerTitle: true,
        title: Text(
          'Cabin Trivia  vs  ${state.opponentName}',
          style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 17,
              fontWeight: FontWeight.w500),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Center(
              child: Text(
                '${state.currentQuestionIndex + 1} / ${state.totalQuestions}',
                style: const TextStyle(
                    color: AppColors.textTertiary, fontSize: 13),
              ),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: _buildBody(state),
      ),
    );
  }

  Widget _buildBody(TriviaGameState state) {
    switch (state.phase) {
      case TriviaPhase.waitingForAccept:
        return _buildWaiting('Waiting for ${state.opponentName} to accept...');
      case TriviaPhase.waitingForQuestion:
        return _buildWaiting('Get ready for the next question...');
      case TriviaPhase.waitingForOpponent:
        return _buildQuestion(state, locked: true,
            statusText: 'Waiting for ${state.opponentName}...');
      case TriviaPhase.waitingForResult:
        return _buildQuestion(state, locked: true,
            statusText: 'Answer sent — waiting for result...');
      case TriviaPhase.answering:
        return _buildQuestion(state, locked: false, statusText: null);
      case TriviaPhase.showingResult:
        return _buildResult(state);
      case TriviaPhase.finished:
        return _buildFinished(state);
    }
  }

  Widget _buildWaiting(String message) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const SizedBox(
            width: 36,
            height: 36,
            child: CircularProgressIndicator(
              color: AppColors.primary,
              strokeWidth: 2,
            ),
          ),
          const SizedBox(height: 24),
          Text(
            message,
            style: const TextStyle(
                color: AppColors.textSecondary, fontSize: 15),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildQuestion(TriviaGameState state,
      {required bool locked, required String? statusText}) {
    final question = state.currentQuestion;
    if (question == null) return _buildWaiting('Loading question...');

    final options = (question['options'] as List).cast<String>();
    final labels = ['A', 'B', 'C', 'D'];

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Score bar ──
          _ScoreBar(
            myScore: state.myScore,
            opponentScore: state.opponentScore,
            opponentName: state.opponentName,
          ),

          const SizedBox(height: 20),

          // ── Timer ring + seconds ──
          Center(
            child: SizedBox(
              width: 64,
              height: 64,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  AnimatedBuilder(
                    animation: _timerAnim,
                    builder: (_, __) => CircularProgressIndicator(
                      value: 1.0 - _timerAnim.value,
                      color: _secondsLeft <= 5
                          ? AppColors.error
                          : AppColors.primary,
                      backgroundColor:
                          AppColors.primary.withValues(alpha: 0.15),
                      strokeWidth: 4,
                    ),
                  ),
                  Text(
                    '$_secondsLeft',
                    style: TextStyle(
                      color: _secondsLeft <= 5
                          ? AppColors.error
                          : AppColors.textPrimary,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 24),

          // ── Question text ──
          Text(
            question['q'] as String,
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 18,
              fontWeight: FontWeight.w500,
              height: 1.4,
            ),
          ),

          const SizedBox(height: 24),

          // ── Answer grid ──
          Expanded(
            child: GridView.count(
              crossAxisCount: 2,
              childAspectRatio: 2.2,
              crossAxisSpacing: 10,
              mainAxisSpacing: 10,
              physics: const NeverScrollableScrollPhysics(),
              children: List.generate(4, (i) {
                final isSelected = _tappedIndex == i;
                return GestureDetector(
                  onTap: locked || _tappedIndex != null
                      ? null
                      : () => _onAnswerTapped(i),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? AppColors.primary.withValues(alpha: 0.2)
                          : AppColors.surface,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: isSelected
                            ? AppColors.primary
                            : AppColors.glassBorder,
                        width: isSelected ? 1.5 : 1,
                      ),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 24,
                          height: 24,
                          decoration: BoxDecoration(
                            color: AppColors.surfaceLight,
                            shape: BoxShape.circle,
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            labels[i],
                            style: TextStyle(
                              color: isSelected
                                  ? AppColors.primary
                                  : AppColors.textTertiary,
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            options[i],
                            style: TextStyle(
                              color: isSelected
                                  ? AppColors.textPrimary
                                  : AppColors.textSecondary,
                              fontSize: 12,
                              height: 1.3,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }),
            ),
          ),

          if (statusText != null)
            Center(
              child: Text(
                statusText,
                style: const TextStyle(
                    color: AppColors.textTertiary, fontSize: 13),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildResult(TriviaGameState state) {
    final question = state.currentQuestion;
    if (question == null) return _buildWaiting('');

    final options = (question['options'] as List).cast<String>();
    final correct = state.correctAnswerIndex ?? -1;
    final myAnswer = state.myAnswerIndex ?? -1;
    final iGotItRight = myAnswer == correct;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _ScoreBar(
            myScore: state.myScore,
            opponentScore: state.opponentScore,
            opponentName: state.opponentName,
          ),
          const SizedBox(height: 24),

          // ── Result banner ──
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 14),
            decoration: BoxDecoration(
              color: iGotItRight
                  ? const Color(0xFF1A3A2A)
                  : const Color(0xFF3A1A1A),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: iGotItRight
                    ? const Color(0xFF2ECC71).withValues(alpha: 0.4)
                    : AppColors.error.withValues(alpha: 0.4),
              ),
            ),
            alignment: Alignment.center,
            child: Text(
              iGotItRight ? 'Correct' : (myAnswer == -1 ? 'Time\'s up' : 'Wrong'),
              style: TextStyle(
                color: iGotItRight
                    ? const Color(0xFF2ECC71)
                    : AppColors.error,
                fontSize: 18,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),

          const SizedBox(height: 20),
          Text(
            question['q'] as String,
            style: const TextStyle(
                color: AppColors.textSecondary, fontSize: 15, height: 1.4),
          ),
          const SizedBox(height: 16),

          // ── Options with color coding ──
          ...List.generate(4, (i) {
            final isCorrect = i == correct;
            final isMyWrongAnswer = i == myAnswer && myAnswer != correct;
            Color borderColor = AppColors.glassBorder;
            Color bgColor = AppColors.surface;
            if (isCorrect) {
              borderColor = const Color(0xFF2ECC71).withValues(alpha: 0.6);
              bgColor = const Color(0xFF1A3A2A);
            } else if (isMyWrongAnswer) {
              borderColor = AppColors.error.withValues(alpha: 0.6);
              bgColor = const Color(0xFF3A1A1A);
            }
            return Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: bgColor,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: borderColor),
              ),
              child: Text(
                options[i],
                style: TextStyle(
                  color: isCorrect
                      ? const Color(0xFF2ECC71)
                      : isMyWrongAnswer
                          ? AppColors.error
                          : AppColors.textTertiary,
                  fontSize: 14,
                ),
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildFinished(TriviaGameState state) {
    final iWon = state.myScore > state.opponentScore;
    final isTie = state.myScore == state.opponentScore;

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            isTie
                ? 'It\'s a tie'
                : (iWon ? 'You won' : 'You lost'),
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 28,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '${state.myScore} – ${state.opponentScore}',
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 20,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'You  vs  ${state.opponentName}',
            style: const TextStyle(
                color: AppColors.textTertiary, fontSize: 14),
          ),
          const SizedBox(height: 48),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              OutlinedButton(
                onPressed: () {
                  ref.read(triviaGameProvider.notifier).reset();
                  context.go('/matches');
                },
                child: const Text('Back'),
              ),
              const SizedBox(width: 16),
              if (state.isHost)
                ElevatedButton(
                  onPressed: () {
                    final newGameId = const Uuid().v4();
                    final opponentId = state.opponentId;
                    final opponentName = state.opponentName;
                    ref.read(triviaGameProvider.notifier)
                        .startGame(opponentId, opponentName, newGameId);
                    ref.read(appControllerProvider).sendGameMessage(
                      opponentId,
                      GameMessage(
                        gameId: newGameId,
                        gameType: GameType.trivia,
                        type: GameMessageType.invite,
                        payload: {},
                      ),
                    );
                  },
                  child: const Text('Play Again'),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Score bar widget ────────────────────────────────────────────────────────

class _ScoreBar extends StatelessWidget {
  final int myScore;
  final int opponentScore;
  final String opponentName;

  const _ScoreBar({
    required this.myScore,
    required this.opponentScore,
    required this.opponentName,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.glassBorder),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              children: [
                Text(
                  '$myScore',
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Text(
                  'You',
                  style:
                      TextStyle(color: AppColors.textTertiary, fontSize: 12),
                ),
              ],
            ),
          ),
          const Text(
            '—',
            style: TextStyle(color: AppColors.textTertiary, fontSize: 18),
          ),
          Expanded(
            child: Column(
              children: [
                Text(
                  '$opponentScore',
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  opponentName,
                  style: const TextStyle(color: AppColors.textTertiary, fontSize: 12),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
