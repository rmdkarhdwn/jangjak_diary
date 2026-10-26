import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../theme/diary_theme.dart';

class DesignIcon extends StatelessWidget {
  const DesignIcon(
    this.name, {
    super.key,
    required this.width,
    required this.height,
  });

  final String name;
  final double width;
  final double height;

  @override
  Widget build(BuildContext context) => SvgPicture.asset(
    'assets/figma/$name.svg',
    width: width,
    height: height,
    excludeFromSemantics: true,
  );
}

class FireplaceArt extends StatelessWidget {
  const FireplaceArt({super.key, required this.name, this.scale = 1});

  final String name;
  final double scale;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 300 * scale,
    height: 320 * scale,
    child: Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned(
          top: 0,
          left: 0,
          width: 302 * scale,
          height: 324 * scale,
          // Rasterized from the unchanged Figma SVG to preserve SVG filter shadows.
          child: Image.asset(
            'assets/figma/$name.png',
            fit: BoxFit.fill,
            excludeFromSemantics: true,
            filterQuality: FilterQuality.high,
          ),
        ),
      ],
    ),
  );
}

class HomeAction extends StatelessWidget {
  const HomeAction({
    super.key,
    required this.label,
    required this.onTap,
    this.primary = false,
    this.scale = 1,
  });

  final String label;
  final VoidCallback onTap;
  final bool primary;
  final double scale;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: label,
    excludeSemantics: true,
    child: Material(
      type: MaterialType.transparency,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(24),
        child: SizedBox(
          width: 86 * scale,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                height: 74 * scale,
                child: Center(
                  child: Container(
                    width: (primary ? 68 : 56) * scale,
                    height: (primary ? 68 : 56) * scale,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: primary ? null : const Color(0x0DECE1D5),
                      gradient: primary
                          ? const LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [Color(0xFFF5E9D8), Color(0xFFDED0BA)],
                            )
                          : null,
                      border: primary
                          ? null
                          : Border.all(color: const Color(0x57E9E0D7)),
                      boxShadow: primary
                          ? const [
                              BoxShadow(
                                color: Color(0x2634313F),
                                offset: Offset(0, 6),
                                blurRadius: 14,
                              ),
                            ]
                          : null,
                    ),
                    child: Center(
                      child: DesignIcon(
                        primary ? 'add_log' : 'history',
                        width: (primary ? 29 : 23) * scale,
                        height: (primary ? 29 : 23) * scale,
                      ),
                    ),
                  ),
                ),
              ),
              SizedBox(height: 10 * scale),
              Text(
                label,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: DiaryTheme.cream.withValues(alpha: primary ? 1 : .84),
                  fontWeight: FontWeight.w500,
                  fontSize: (primary ? 14 : 13) * scale,
                  height: primary ? 22 / 14 : 22 / 13,
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class InterestIndicator extends StatelessWidget {
  const InterestIndicator({
    super.key,
    required this.count,
    required this.selected,
    required this.onSelected,
    this.scale = 1,
  });

  final int count;
  final int selected;
  final ValueChanged<int> onSelected;
  final double scale;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 16 * scale,
    child: Center(
      child: Semantics(
        label: '${selected + 1} / $count번째 불',
        child: SizedBox(
          width: (count * 12 + 16) * scale,
          height: 16 * scale,
          child: Stack(
            alignment: Alignment.center,
            children: [
              if (count == 4 && selected == 1)
                DesignIcon(
                  'page_indicator',
                  width: 64 * scale,
                  height: 16 * scale,
                )
              else
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(
                    count,
                    (index) => Padding(
                      padding: EdgeInsets.symmetric(horizontal: 4 * scale),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        width: (selected == index ? 14 : 4) * scale,
                        height: 4 * scale,
                        decoration: BoxDecoration(
                          color: DiaryTheme.cream.withValues(
                            alpha: selected == index ? 1 : .8,
                          ),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                  ),
                ),
              Row(
                children: List.generate(
                  count,
                  (index) => Expanded(
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => onSelected(index),
                      child: Semantics(
                        button: true,
                        label: '${index + 1}번째 불로 이동',
                        child: const SizedBox.expand(),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
