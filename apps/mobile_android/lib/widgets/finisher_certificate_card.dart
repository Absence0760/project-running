import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../finisher_certificate.dart';
import '../l10n/date_format.dart';
import '../l10n/gen/app_localizations.dart';
import '../l10n/locale_support.dart';
import '../preferences.dart';
import 'top_banner.dart';

/// Opens a modal sheet showing the finisher certificate for an eligible
/// finisher and lets them save / share the rendered PNG via the OS share sheet.
/// Mobile equivalent of web's downloadable certificate: web rasterises an SVG
/// to a PNG download; here a [RepaintBoundary] grab of [FinisherCertificateCard]
/// feeds `share_plus`.
Future<void> showFinisherCertificateSheet(
  BuildContext context, {
  required String eventTitle,
  required String finisherName,
  required int durationS,
  required double distanceM,
  required int? rank,
  required DateTime date,
  String? clubName,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _CertificateSheet(
      eventTitle: eventTitle,
      finisherName: finisherName,
      durationS: durationS,
      distanceM: distanceM,
      rank: rank,
      date: date,
      clubName: clubName,
    ),
  );
}

class _CertificateSheet extends StatefulWidget {
  final String eventTitle;
  final String finisherName;
  final int durationS;
  final double distanceM;
  final int? rank;
  final DateTime date;
  final String? clubName;

  const _CertificateSheet({
    required this.eventTitle,
    required this.finisherName,
    required this.durationS,
    required this.distanceM,
    required this.rank,
    required this.date,
    required this.clubName,
  });

  @override
  State<_CertificateSheet> createState() => _CertificateSheetState();
}

class _CertificateSheetState extends State<_CertificateSheet> {
  final GlobalKey _cardKey = GlobalKey();
  bool _capturing = false;

  Future<void> _shareImage() async {
    if (_capturing) return;
    final l10n = AppLocalizations.of(context);
    setState(() => _capturing = true);
    try {
      await WidgetsBinding.instance.endOfFrame;
      final boundary =
          _cardKey.currentContext!.findRenderObject() as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 3.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) return;
      final bytes = byteData.buffer.asUint8List();

      final safe = widget.eventTitle
          .replaceAll(RegExp('[^A-Za-z0-9]+'), '-')
          .toLowerCase();
      final tmp = await getTemporaryDirectory();
      final file = File('${tmp.path}/threkir-certificate-$safe.png');
      await file.writeAsBytes(bytes);

      await Share.shareXFiles(
        [XFile(file.path, mimeType: 'image/png')],
        text: l10n.clubEventCertificateShareText(widget.eventTitle),
      );
    } catch (e) {
      debugPrint('Failed to capture finisher certificate: $e');
      if (mounted) {
        showTopBanner(
            context, AppLocalizations.of(context).clubEventCertificateFailed);
      }
    } finally {
      if (mounted) setState(() => _capturing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + mq.viewInsets.bottom),
        child: Container(
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            borderRadius: BorderRadius.circular(20),
          ),
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(l10n.clubEventDownloadCertificate,
                  style: theme.textTheme.titleMedium),
              const SizedBox(height: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: AspectRatio(
                  aspectRatio: 1400 / 990,
                  child: RepaintBoundary(
                    key: _cardKey,
                    child: FinisherCertificateCard(
                      eventTitle: widget.eventTitle,
                      finisherName: widget.finisherName,
                      durationS: widget.durationS,
                      distanceM: widget.distanceM,
                      rank: widget.rank,
                      date: widget.date,
                      clubName: widget.clubName,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _capturing ? null : _shareImage,
                  icon: _capturing
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.ios_share),
                  label: Text(l10n.clubEventCertificateShare),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The finisher certificate itself — a landscape card mirroring web's SVG:
/// cream ground, amber double border, finisher name as the hero, time +
/// distance + placing beneath. Wrap in a [RepaintBoundary] and grab via
/// [RenderRepaintBoundary.toImage] to share as a PNG. Designed for a
/// 1400:990 aspect ratio (web's CERT_WIDTH:CERT_HEIGHT).
class FinisherCertificateCard extends StatelessWidget {
  final String eventTitle;
  final String finisherName;
  final int durationS;
  final double distanceM;
  final int? rank;
  final DateTime date;
  final String? clubName;

  const FinisherCertificateCard({
    super.key,
    required this.eventTitle,
    required this.finisherName,
    required this.durationS,
    required this.distanceM,
    required this.rank,
    required this.date,
    this.clubName,
  });

  static const Color _accent = Color(0xFFB45309);
  static const Color _ink = Color(0xFF1F2937);
  static const Color _muted = Color(0xFF6B7280);
  static const Color _ground = Color(0xFFFFFDF7);

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final useMiles = activeDistanceUnit == DistanceUnit.mi;
    final stats = <String>[
      '${l10n.clubEventCertificateTime} ${formatCertificateTime(durationS)}',
      '${l10n.clubEventCertificateDistance} '
          '${formatCertificateDistance(distanceM, useMiles: useMiles)}',
      if (rank != null && rank! > 0)
        l10n.clubEventCertificatePlace(ordinalPlace(rank!)),
    ];

    return Container(
      color: _ground,
      child: LayoutBuilder(
        builder: (context, constraints) {
          // Border insets scale with the card so the frame holds its
          // proportions at any render size (preview vs 3x capture).
          final inset = constraints.maxWidth * 0.02;
          return Padding(
            padding: EdgeInsets.all(inset),
            child: Container(
              decoration: BoxDecoration(
                border: Border.all(color: _accent, width: 4),
              ),
              child: Container(
                margin: EdgeInsets.all(inset * 0.6),
                decoration: BoxDecoration(
                  border: Border.all(
                    color: _accent.withValues(alpha: 0.5),
                    width: 1.5,
                  ),
                ),
                padding: EdgeInsets.symmetric(
                  horizontal: constraints.maxWidth * 0.06,
                  vertical: constraints.maxHeight * 0.05,
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Column(
                      children: [
                        const Text(
                          'THREKIR',
                          style: TextStyle(
                            color: _accent,
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 4,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          l10n.clubEventCertificateHeading,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: _ink,
                            fontSize: 26,
                            fontWeight: FontWeight.w700,
                            fontFamily: 'serif',
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          l10n.clubEventCertificateCertifies,
                          style: const TextStyle(color: _muted, fontSize: 13),
                        ),
                      ],
                    ),
                    Column(
                      children: [
                        Text(
                          finisherName,
                          textAlign: TextAlign.center,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: _ink,
                            fontSize: 40,
                            fontWeight: FontWeight.w700,
                            fontFamily: 'serif',
                          ),
                        ),
                        Container(
                          margin: const EdgeInsets.only(top: 6),
                          height: 1,
                          width: constraints.maxWidth * 0.5,
                          color: _accent.withValues(alpha: 0.5),
                        ),
                      ],
                    ),
                    Column(
                      children: [
                        Text(
                          l10n.clubEventCertificateCompleted,
                          style: const TextStyle(color: _muted, fontSize: 14),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          eventTitle,
                          textAlign: TextAlign.center,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: _accent,
                            fontSize: 22,
                            fontWeight: FontWeight.w700,
                            fontFamily: 'serif',
                          ),
                        ),
                      ],
                    ),
                    Text(
                      stats.join('   •   '),
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: _ink,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Column(
                      children: [
                        Text(
                          formatDateMed(date, activeLocaleTag),
                          style: const TextStyle(color: _muted, fontSize: 12),
                        ),
                        if (clubName != null && clubName!.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(
                            clubName!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: _muted, fontSize: 11),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
