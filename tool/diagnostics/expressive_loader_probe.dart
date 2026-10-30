// Offline Android-engine probe. Not imported by the production entry point.
// flutter run --release -t tool/diagnostics/expressive_loader_probe.dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:get/get.dart';
import 'package:jhentai/src/config/ui_config.dart';
import 'package:jhentai/src/model/gallery_url.dart';
import 'package:jhentai/src/pages/details/details_page.dart';
import 'package:jhentai/src/pages/details/details_page_logic.dart';
import 'package:jhentai/src/widget/expressive_loading_indicator.dart';

void main() => runApp(GetMaterialApp(
      theme: ThemeData(colorSchemeSeed: Colors.deepPurple),
      home: const _Probe(),
    ));

class _Logic extends DetailsPageLogic {
  _Logic() : super.preview() {
    state.galleryUrl = GalleryUrl.parse('https://e-hentai.org/g/1/0123456789/');
  }
  @override
  void onReady() {} // Deliberately no production network or account startup.
}

class _Probe extends StatefulWidget {
  const _Probe();
  @override
  State<_Probe> createState() => _ProbeState();
}

class _ProbeState extends State<_Probe> {
  late final _Logic logic;
  late final DetailsPage details;
  Timer? _sample;
  bool enabled = true;
  bool reduced = false;
  bool accessible = const bool.fromEnvironment('JH_PROBE_ACCESSIBLE');

  @override
  void initState() {
    super.initState();
    logic = _Logic();
    details = DetailsPage.preview()
      ..logic = logic
      ..state = logic.state;
    // Read clock/flags without setState or forcing frames: manual widget-test
    // pumping previously masked failures in real-engine scheduling.
    _sample = Timer.periodic(const Duration(seconds: 1), (_) => _readClocks());
  }

  void _readClocks() {
    void visit(Element element) {
      if (element.widget is ExpressiveLoadingIndicator) {
        final media = MediaQuery.of(element);
        void findPainter(Element child) {
          if (child.widget is CustomPaint) {
            final render = child.renderObject! as RenderCustomPaint;
            final dynamic painter = render.painter;
            final Duration elapsed = painter.clock.elapsed as Duration;
            // ignore: avoid_print
            print('LOADER_PROBE elapsed=${elapsed.inMilliseconds} '
                'lifecycle=${WidgetsBinding.instance.lifecycleState?.name} '
                'tickerMode=${TickerMode.getValuesNotifier(element).value.enabled} '
                'disableAnimations=${media.disableAnimations} '
                'accessibleNavigation=${media.accessibleNavigation} '
                'attached=${render.attached}');
          }
          child.visitChildren(findPainter);
        }

        element.visitChildren(findPainter);
      }
      element.visitChildren(visit);
    }

    if (mounted) {
      context.visitChildElements(visit);
    }
  }

  @override
  void dispose() {
    _sample?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Offline loading probe')),
        body: Column(children: [
          Wrap(children: [
            TextButton(
                onPressed: () => setState(() => enabled = !enabled),
                child: const Text('TickerMode')),
            TextButton(
                onPressed: () => setState(() => reduced = !reduced),
                child: const Text('Reduced motion')),
            TextButton(
                onPressed: () => setState(() => accessible = !accessible),
                child: const Text('Accessible navigation')),
            TextButton(
                onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(builder: (_) => const _Probe())),
                child: const Text('Push details')),
            TextButton(
                onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                        builder: (_) => Scaffold(
                            appBar: AppBar(title: const Text('Covered'))))),
                child: const Text('Cover')),
          ]),
          Expanded(
            child: MediaQuery(
              data: MediaQuery.of(context).copyWith(
                  disableAnimations: reduced, accessibleNavigation: accessible),
              child: TickerMode(
                enabled: enabled,
                child: CustomScrollView(slivers: [
                  details.buildDetail(context),
                  const SliverToBoxAdapter(
                      child:
                          Text('Shared loader', textAlign: TextAlign.center)),
                  const SliverToBoxAdapter(
                      child: Center(
                          child: Builder(builder: UIConfig.loadingAnimation))),
                ]),
              ),
            ),
          ),
        ]),
      );
}
