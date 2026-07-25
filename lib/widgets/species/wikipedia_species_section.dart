import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../models/wikipedia_species_content.dart';

class WikipediaSpeciesSection extends StatefulWidget {
  const WikipediaSpeciesSection({
    super.key,
    required this.future,
    this.localImageAssetPath,
  });

  final Future<WikipediaSpeciesContent> future;
  final String? localImageAssetPath;

  @override
  State<WikipediaSpeciesSection> createState() =>
      _WikipediaSpeciesSectionState();
}

class _WikipediaSpeciesSectionState extends State<WikipediaSpeciesSection> {
  bool _descriptionExpanded = false;

  Future<void> _openUrl(String? value) async {
    final uri = Uri.tryParse(value ?? '');
    if (uri != null) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<WikipediaSpeciesContent>(
      future: widget.future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const _WikipediaCard(
            title: 'About this species',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                LinearProgressIndicator(minHeight: 2),
                SizedBox(height: 8),
                Text(
                  'Loading Wikipedia information…',
                  key: Key('wikipedia-loading'),
                  style: TextStyle(color: Color(0xCCFFFFFF)),
                ),
              ],
            ),
          );
        }
        final content = snapshot.data;
        if (content == null || content.status != WikipediaMatchStatus.matched) {
          final message = switch (content?.status) {
            WikipediaMatchStatus.notFound || WikipediaMatchStatus.ambiguous =>
              'No Wikipedia article was found for this species.',
            _ => 'Wikipedia information is currently unavailable.',
          };
          return _WikipediaCard(
            title: 'About this species',
            child: Text(
              message,
              style: const TextStyle(color: Color(0xCCFFFFFF)),
            ),
          );
        }

        final summary = content.summaryExtract?.trim() ?? '';
        final description = content.descriptionText?.trim() ?? '';
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _ReferenceImage(
              imageUrl: content.thumbnailUrl ?? content.originalImageUrl,
              localAssetPath: widget.localImageAssetPath,
              attribution: content.imageAttribution,
              license: content.imageLicense,
              onAttributionTap: content.imageSourceUrl == null
                  ? null
                  : () => _openUrl(content.imageSourceUrl),
            ),
            const SizedBox(height: 12),
            _WikipediaCard(
              title: 'About this species',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if ((content.pageDescription ?? '').trim().isNotEmpty) ...[
                    Text(
                      content.pageDescription!.trim(),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 7),
                  ],
                  if (summary.isNotEmpty)
                    Text(
                      summary,
                      style: const TextStyle(
                        color: Color(0xCCFFFFFF),
                        height: 1.45,
                      ),
                    ),
                  if (content.articleUrl != null) ...[
                    const SizedBox(height: 7),
                    TextButton.icon(
                      onPressed: () => _openUrl(content.articleUrl),
                      icon: const Icon(Icons.open_in_new, size: 17),
                      label: const Text('View on Wikipedia'),
                    ),
                  ],
                  if (content.isStale) ...[
                    const SizedBox(height: 6),
                    const Text(
                      'Showing previously saved species information.',
                      style: TextStyle(color: Color(0xFFFFE8A3), fontSize: 12),
                    ),
                  ],
                ],
              ),
            ),
            if (description.isNotEmpty || summary.isNotEmpty) ...[
              const SizedBox(height: 12),
              _WikipediaCard(
                title: description.isEmpty ? 'Overview' : 'Description',
                child: _ExpandableDescription(
                  text: description.isEmpty ? summary : description,
                  expanded: _descriptionExpanded,
                  onToggle: () => setState(
                    () => _descriptionExpanded = !_descriptionExpanded,
                  ),
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}

class _ReferenceImage extends StatelessWidget {
  const _ReferenceImage({
    required this.imageUrl,
    required this.localAssetPath,
    required this.attribution,
    required this.license,
    required this.onAttributionTap,
  });

  final String? imageUrl;
  final String? localAssetPath;
  final String? attribution;
  final String? license;
  final VoidCallback? onAttributionTap;

  @override
  Widget build(BuildContext context) {
    final localPath = localAssetPath?.trim() ?? '';
    final remoteUrl = imageUrl?.trim() ?? '';
    Widget image;
    if (remoteUrl.isNotEmpty) {
      image = Image.network(
        remoteUrl,
        fit: BoxFit.cover,
        filterQuality: FilterQuality.medium,
        loadingBuilder: (context, child, progress) => progress == null
            ? child
            : const Center(child: CircularProgressIndicator()),
        errorBuilder: (_, _, _) => _ImageFallback(localPath: localPath),
      );
    } else {
      image = _ImageFallback(localPath: localPath);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Reference image',
          key: Key('wikipedia-reference-image-label'),
          style: TextStyle(
            color: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: AspectRatio(aspectRatio: 4 / 3, child: image),
        ),
        if ((attribution ?? '').trim().isNotEmpty ||
            (license ?? '').trim().isNotEmpty) ...[
          const SizedBox(height: 6),
          InkWell(
            onTap: onAttributionTap,
            child: Text(
              [
                if ((attribution ?? '').trim().isNotEmpty) attribution!.trim(),
                if ((license ?? '').trim().isNotEmpty) license!.trim(),
              ].join(' · '),
              style: const TextStyle(
                color: Color(0xCCFFFFFF),
                fontSize: 10.5,
                decoration: TextDecoration.underline,
                decorationColor: Color(0x99FFFFFF),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _ImageFallback extends StatelessWidget {
  const _ImageFallback({required this.localPath});

  final String localPath;

  @override
  Widget build(BuildContext context) {
    if (localPath.isNotEmpty) {
      return Image.asset(
        localPath,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => const _FungiPlaceholder(),
      );
    }
    return const _FungiPlaceholder();
  }
}

class _FungiPlaceholder extends StatelessWidget {
  const _FungiPlaceholder();

  @override
  Widget build(BuildContext context) => const ColoredBox(
    color: Color(0x331F4E3D),
    child: Center(
      child: Icon(Icons.nature_outlined, color: Colors.white70, size: 52),
    ),
  );
}

class _ExpandableDescription extends StatelessWidget {
  const _ExpandableDescription({
    required this.text,
    required this.expanded,
    required this.onToggle,
  });

  final String text;
  final bool expanded;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    const limit = 720;
    final canExpand = text.length > limit;
    final visible = !canExpand || expanded
        ? text
        : '${text.substring(0, limit).trimRight()}…';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          visible,
          style: const TextStyle(color: Color(0xCCFFFFFF), height: 1.45),
        ),
        if (canExpand)
          TextButton(
            key: const Key('wikipedia-description-toggle'),
            onPressed: onToggle,
            child: Text(expanded ? 'Show less' : 'Show more'),
          ),
      ],
    );
  }
}

class _WikipediaCard extends StatelessWidget {
  const _WikipediaCard({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: Colors.white.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(14),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 8),
        child,
      ],
    ),
  );
}
