import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/widgets.dart';
import 'package:watch_it/watch_it.dart';
import 'package:multi_split_view/src/area.dart';
import 'package:multi_split_view/src/controller.dart';
import 'package:multi_split_view/src/divider_tap_typedefs.dart';
import 'package:multi_split_view/src/divider_widget.dart';
import 'package:multi_split_view/src/internal/initial_drag.dart';
import 'package:multi_split_view/src/internal/sizes_cache.dart';
import 'package:multi_split_view/src/theme_data.dart';
import 'package:multi_split_view/src/theme_widget.dart';
import 'package:multi_split_view/src/typedefs.dart';
import 'package:get_it/get_it.dart';

/// A widget to provides horizontal or vertical multiple split view.
class MultiSplitView extends StatelessWidget with WatchItMixin {
  static const Axis defaultAxis = Axis.horizontal;

  /// Creates an [MultiSplitView].
  ///
  /// The default value for [axis] argument is [Axis.horizontal].
  /// The [children] argument is required.
  /// The sum of the [initialWeights] cannot exceed 1.
  /// The [initialWeights] parameter will be ignored if the [controller]
  /// has been provided.
  MultiSplitView({
    Key? key,
    this.axis = MultiSplitView.defaultAxis,
    required this.children,
    this.controller,
    this.dividerBuilder,
    this.onWeightChange,
    this.onDividerTap,
    this.onDividerDoubleTap,
    this.resizable = true,
    this.antiAliasingWorkaround = true,
    List<Area>? initialAreas,
    this.diInstance,
  }) : initialAreas = initialAreas != null ? List.from(initialAreas) : null,
       super(key: key) {
    // Register state management in DI if not already registered
    final di = diInstance ?? GetIt.instance;
    if (!di.isRegistered<MultiSplitViewState>()) {
      di.registerSingleton<MultiSplitViewState>(MultiSplitViewState());
    }
  }

  final Axis axis;
  final List<Widget> children;
  final MultiSplitViewController? controller;
  final List<Area>? initialAreas;
  final GetIt? diInstance;

  /// Signature for when a divider tap has occurred.
  final DividerTapCallback? onDividerTap;

  /// Signature for when a divider double tap has occurred.
  final DividerTapCallback? onDividerDoubleTap;

  /// Defines a builder of dividers. Overrides the default divider
  /// created by the theme.
  final DividerBuilder? dividerBuilder;

  /// Indicates whether it is resizable. The default value is [TRUE].
  final bool resizable;

  /// Function to listen children weight change.
  /// The listener will run on the parent's resize or
  /// on the dragging end of the divisor.
  final OnWeightChange? onWeightChange;

  /// Enables a workaround for https://github.com/flutter/flutter/issues/14288
  final bool antiAliasingWorkaround;

  @override
  Widget build(BuildContext context) {
    // Get state from DI
    final di = diInstance ?? GetIt.instance;
    final state = di<MultiSplitViewState>();
    
    // Get or create controller
    final controller = this.controller ?? MultiSplitViewController(areas: initialAreas);
    
    // Watch reactive state
    final draggingDividerIndex = watchValue((MultiSplitViewState s) => s.draggingDividerIndexNotifier);
    final hoverDividerIndex = watchValue((MultiSplitViewState s) => s.hoverDividerIndexNotifier);
    final sizesCache = watchValue((MultiSplitViewState s) => s.sizesCacheNotifier);
    final weightsHashCode = watchValue((MultiSplitViewState s) => s.weightsHashCodeNotifier);
    final lastAreasUpdateHash = watchValue((MultiSplitViewState s) => s.lastAreasUpdateHashNotifier);
    final dragRebuildTrigger = watchValue((MultiSplitViewState s) => s.dragRebuildTriggerNotifier);
    
    // Defer state updates to avoid setState during build
    if (lastAreasUpdateHash != controller.areasUpdateHash) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        state.draggingDividerIndex = null;
        state.lastAreasUpdateHash = controller.areasUpdateHash;
      });
    }
    
    if (children.isNotEmpty) {
      MultiSplitViewThemeData themeData = MultiSplitViewTheme.of(context);

      return LayoutBuilder(builder: (context, constraints) {
        final double fullSize = axis == Axis.horizontal
            ? constraints.maxWidth
            : constraints.maxHeight;

        controller.fixWeights(
            childrenCount: children.length,
            fullSize: fullSize,
            dividerThickness: themeData.dividerThickness);
        
        // Defer sizesCache update to avoid setState during build
        if (sizesCache == null ||
            sizesCache.childrenCount != children.length ||
            sizesCache.fullSize != fullSize) {
          final newSizesCache = SizesCache(
              areas: controller.areas,
              fullSize: fullSize,
              dividerThickness: themeData.dividerThickness);
          WidgetsBinding.instance.addPostFrameCallback((_) {
            state.sizesCache = newSizesCache;
          });
          // Use the new cache for this build
          return _buildWithSizesCache(context, newSizesCache, themeData, controller, state, draggingDividerIndex, hoverDividerIndex, weightsHashCode);
        } else {
          // Use existing cache but make sure it's up to date with any drag changes
          final currentSizesCache = sizesCache;
          return _buildWithSizesCache(context, currentSizesCache, themeData, controller, state, draggingDividerIndex, hoverDividerIndex, weightsHashCode);
        }
      });
    }
    return Container();
  }
  
  Widget _buildWithSizesCache(
      BuildContext context,
      SizesCache sizesCache,
      MultiSplitViewThemeData themeData,
      MultiSplitViewController controller,
      MultiSplitViewState state,
      int? draggingDividerIndex,
      int? hoverDividerIndex,
      int? weightsHashCode) {
    List<Widget> childWidgets = [];

    sizesCache.iterate(child: (int index, double start, double end) {
      childWidgets.add(_buildPositioned(
          start: start, end: end, child: children[index]));
    }, divider: (int index, double start, double end) {
      bool highlighted = (draggingDividerIndex == index ||
          (draggingDividerIndex == null && hoverDividerIndex == index));
      Widget dividerWidget = dividerBuilder != null
          ? dividerBuilder!(
              axis == Axis.horizontal
                  ? Axis.vertical
                  : Axis.horizontal,
              index,
              resizable,
              draggingDividerIndex == index,
              highlighted,
              themeData)
          : DividerWidget(
              axis: axis == Axis.horizontal
                  ? Axis.vertical
                  : Axis.horizontal,
              index: index,
              themeData: themeData,
              highlighted: highlighted,
              resizable: resizable,
              dragging: draggingDividerIndex == index);
      if (resizable) {
        dividerWidget = GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTap: () => _onDividerTap(index),
            onDoubleTap: () => _onDividerDoubleTap(index),
            onHorizontalDragDown: axis == Axis.vertical
                ? null
                : (detail) {
                    state.draggingDividerIndex = index;
                    final pos = _position(context, detail.globalPosition);
                    _updateInitialDrag(index, pos.dx, state, sizesCache);
                  },
            onHorizontalDragCancel:
                axis == Axis.vertical ? null : () => _onDragCancel(state),
            onHorizontalDragEnd: axis == Axis.vertical
                ? null
                : (detail) => _onDragEnd(state, controller, sizesCache),
            onHorizontalDragUpdate: axis == Axis.vertical
                ? null
                : (detail) {
                    if (draggingDividerIndex == null) {
                      return;
                    }
                    final pos = _position(context, detail.globalPosition);
                    double diffX = pos.dx - state.initialDrag!.initialDragPos;

                    _updateDifferentWeights(
                        childIndex: index, diffPos: diffX, pos: pos.dx, state: state, sizesCache: sizesCache);
                  },
            onVerticalDragDown: axis == Axis.horizontal
                ? null
                : (detail) {
                    state.draggingDividerIndex = index;
                    final pos = _position(context, detail.globalPosition);
                    _updateInitialDrag(index, pos.dy, state, sizesCache);
                  },
            onVerticalDragCancel: axis == Axis.horizontal
                ? null
                : () => _onDragCancel(state),
            onVerticalDragEnd: axis == Axis.horizontal
                ? null
                : (detail) => _onDragEnd(state, controller, sizesCache),
            onVerticalDragUpdate: axis == Axis.horizontal
                ? null
                : (detail) {
                    if (draggingDividerIndex == null) {
                      return;
                    }
                    final pos = _position(context, detail.globalPosition);
                    double diffY = pos.dy - state.initialDrag!.initialDragPos;
                    _updateDifferentWeights(
                        childIndex: index, diffPos: diffY, pos: pos.dy, state: state, sizesCache: sizesCache);
                  },
            child: dividerWidget);
        dividerWidget = _mouseRegion(
            index: index,
            axis: axis == Axis.horizontal
                ? Axis.vertical
                : Axis.horizontal,
            dividerWidget: dividerWidget,
            themeData: themeData,
            state: state);
      }
      childWidgets.add(
          _buildPositioned(start: start, end: end, child: dividerWidget));
    });

    // Defer weightsHashCode update to avoid setState during build
    if (onWeightChange != null) {
      int newWeightsHashCode = controller.weightsHashCode;
      if (weightsHashCode != null &&
          weightsHashCode != newWeightsHashCode) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          onWeightChange!();
          state.weightsHashCode = newWeightsHashCode;
        });
      }
    }

    return Stack(children: childWidgets);
  }

  /// Updates the hover divider index.
  void _updatesHoverDividerIndex(
      {int? index, required MultiSplitViewThemeData themeData, required MultiSplitViewState state}) {
    if (state.hoverDividerIndex != index &&
        (themeData.dividerPainter != null || dividerBuilder != null)) {
      state.hoverDividerIndex = index;
    }
  }

  void _onDividerTap(int index) {
    if (onDividerTap != null) {
      onDividerTap!(index);
    }
  }

  void _onDividerDoubleTap(int index) {
    if (onDividerDoubleTap != null) {
      onDividerDoubleTap!(index);
    }
  }

  void _onDragCancel(MultiSplitViewState state) {
    if (state.draggingDividerIndex == null) {
      return;
    }
    state.draggingDividerIndex = null;
  }

  void _onDragEnd(MultiSplitViewState state, MultiSplitViewController controller, SizesCache sizesCache) {
    if (state.draggingDividerIndex == null) {
      return;
    }
    for (int i = 0; i < controller.areasLength; i++) {
      final Area area = controller.getArea(i);
      double size = sizesCache.sizes[i];
      area.updateWeight(size / sizesCache.childrenSize);
    }
    state.draggingDividerIndex = null;
  }

  /// Wraps the divider widget with a [MouseRegion].
  Widget _mouseRegion(
      {required int index,
      required Axis axis,
      required Widget dividerWidget,
      required MultiSplitViewThemeData themeData,
      required MultiSplitViewState state}) {
    MouseCursor cursor = axis == Axis.horizontal
        ? SystemMouseCursors.resizeRow
        : SystemMouseCursors.resizeColumn;
    return MouseRegion(
        cursor: cursor,
        onEnter: (event) =>
            _updatesHoverDividerIndex(index: index, themeData: themeData, state: state),
        onExit: (event) => _updatesHoverDividerIndex(themeData: themeData, state: state),
        child: dividerWidget);
  }

  void _updateInitialDrag(int childIndex, double initialDragPos, MultiSplitViewState state, SizesCache sizesCache) {
    final double initialChild1Size = sizesCache.sizes[childIndex];
    final double initialChild2Size = sizesCache.sizes[childIndex + 1];
    final double minimalChild1Size = sizesCache.minimalSizes[childIndex];
    final double minimalChild2Size = sizesCache.minimalSizes[childIndex + 1];
    final double sumMinimals = minimalChild1Size + minimalChild2Size;
    final double sumSizes = initialChild1Size + initialChild2Size;

    double posLimitStart = 0;
    double posLimitEnd = 0;
    double child1Start = 0;
    double child2End = 0;
    for (int i = 0; i <= childIndex; i++) {
      if (i < childIndex) {
        child1Start += sizesCache.sizes[i];
        child1Start += sizesCache.dividerThickness;
        child2End += sizesCache.sizes[i];
        child2End += sizesCache.dividerThickness;
        posLimitStart += sizesCache.sizes[i];
        posLimitStart += sizesCache.dividerThickness;
        posLimitEnd += sizesCache.sizes[i];
        posLimitEnd += sizesCache.dividerThickness;
      } else if (i == childIndex) {
        posLimitStart += sizesCache.minimalSizes[i];
        posLimitEnd += sizesCache.sizes[i];
        posLimitEnd += sizesCache.dividerThickness;
        posLimitEnd += sizesCache.sizes[i + 1];
        child2End += sizesCache.sizes[i];
        child2End += sizesCache.dividerThickness;
        child2End += sizesCache.sizes[i + 1];
        posLimitEnd = math.max(
            posLimitStart, posLimitEnd - sizesCache.minimalSizes[i + 1]);
      }
    }

    state.initialDrag = InitialDrag(
        initialDragPos: initialDragPos,
        initialChild1Size: initialChild1Size,
        initialChild2Size: initialChild2Size,
        minimalChild1Size: minimalChild1Size,
        minimalChild2Size: minimalChild2Size,
        sumMinimals: sumMinimals,
        sumSizes: sumSizes,
        child1Start: child1Start,
        child2End: child2End,
        posLimitStart: posLimitStart,
        posLimitEnd: posLimitEnd);
    state.initialDrag!.posBeforeMinimalChild1 = initialDragPos < posLimitStart;
    state.initialDrag!.posAfterMinimalChild2 = initialDragPos > posLimitEnd;
  }

  /// Calculates the new weights and sets if they are different from the current one.
  void _updateDifferentWeights(
      {required int childIndex, required double diffPos, required double pos, required MultiSplitViewState state, required SizesCache sizesCache}) {
    if (diffPos == 0) {
      return;
    }

    if (state.initialDrag!.sumMinimals >= state.initialDrag!.sumSizes) {
      // minimals already smaller than available space. Ignoring...
      return;
    }

    double newChild1Size;
    double newChild2Size;

    if (diffPos.isNegative) {
      // divider moving on left/top from initial mouse position
      if (state.initialDrag!.posBeforeMinimalChild1) {
        // can't shrink, already smaller than minimal
        return;
      }
      newChild1Size = math.max(state.initialDrag!.minimalChild1Size,
          state.initialDrag!.initialChild1Size + diffPos);
      newChild2Size = state.initialDrag!.sumSizes - newChild1Size;

      if (state.initialDrag!.posAfterMinimalChild2) {
        if (newChild2Size > state.initialDrag!.minimalChild2Size) {
          state.initialDrag!.posAfterMinimalChild2 = false;
        }
      } else if (newChild2Size < state.initialDrag!.minimalChild2Size) {
        double diff = state.initialDrag!.minimalChild2Size - newChild2Size;
        newChild2Size += diff;
        newChild1Size -= diff;
      }
    } else {
      // divider moving on right/bottom from initial mouse position
      if (state.initialDrag!.posAfterMinimalChild2) {
        // can't shrink, already smaller than minimal
        return;
      }
      newChild2Size = math.max(state.initialDrag!.minimalChild2Size,
          state.initialDrag!.initialChild2Size - diffPos);
      newChild1Size = state.initialDrag!.sumSizes - newChild2Size;

      if (state.initialDrag!.posBeforeMinimalChild1) {
        if (newChild1Size > state.initialDrag!.minimalChild1Size) {
          state.initialDrag!.posBeforeMinimalChild1 = false;
        }
      } else if (newChild1Size < state.initialDrag!.minimalChild1Size) {
        double diff = state.initialDrag!.minimalChild1Size - newChild1Size;
        newChild1Size += diff;
        newChild2Size -= diff;
      }
    }
    if (sizesCache != null && newChild1Size >= 0 && newChild2Size >= 0) {
      // Update both the local cache for immediate visual feedback
      sizesCache.sizes[childIndex] = newChild1Size;
      sizesCache.sizes[childIndex + 1] = newChild2Size;
      
      // Also update the state cache to trigger reactive updates
      // This is safe during drag operations as it's user-initiated
      if (state.sizesCache != null) {
        state.sizesCache!.sizes[childIndex] = newChild1Size;
        state.sizesCache!.sizes[childIndex + 1] = newChild2Size;
      }
      
      // Trigger a rebuild to show the resize immediately
      state.triggerDragRebuild();
    }
  }

  /// Builds an [Offset] for cursor position.
  Offset _position(BuildContext context, Offset globalPosition) {
    final RenderBox container = context.findRenderObject() as RenderBox;
    return container.globalToLocal(globalPosition);
  }

  Positioned _buildPositioned(
      {required double start,
      required double end,
      required Widget child,
      bool last = false}) {
    Positioned positioned = Positioned(
        key: child.key,
        top: axis == Axis.horizontal ? 0 : _convert(start, false),
        bottom: axis == Axis.horizontal ? 0 : _convert(end, last),
        left: axis == Axis.horizontal ? _convert(start, false) : 0,
        right: axis == Axis.horizontal ? _convert(end, last) : 0,
        child: ClipRect(child: child));
    return positioned;
  }

  /// This is a workaround for https://github.com/flutter/flutter/issues/14288
  /// The problem minimizes by avoiding the use of coordinates with
  /// decimal values.
  double _convert(double value, bool last) {
    if (antiAliasingWorkaround && !last) {
      return value.roundToDouble();
    }
    return value;
  }
}

/// State management for MultiSplitView using ValueNotifiers
class MultiSplitViewState {
  final ValueNotifier<int?> draggingDividerIndexNotifier = ValueNotifier<int?>(null);
  final ValueNotifier<int?> hoverDividerIndexNotifier = ValueNotifier<int?>(null);
  final ValueNotifier<SizesCache?> sizesCacheNotifier = ValueNotifier<SizesCache?>(null);
  final ValueNotifier<int?> weightsHashCodeNotifier = ValueNotifier<int?>(null);
  final ValueNotifier<Object?> lastAreasUpdateHashNotifier = ValueNotifier<Object?>(null);
  final ValueNotifier<int> dragRebuildTriggerNotifier = ValueNotifier<int>(0);
  
  InitialDrag? initialDrag;
  
  int? get draggingDividerIndex => draggingDividerIndexNotifier.value;
  set draggingDividerIndex(int? value) => draggingDividerIndexNotifier.value = value;
  
  int? get hoverDividerIndex => hoverDividerIndexNotifier.value;
  set hoverDividerIndex(int? value) => hoverDividerIndexNotifier.value = value;
  
  SizesCache? get sizesCache => sizesCacheNotifier.value;
  set sizesCache(SizesCache? value) => sizesCacheNotifier.value = value;
  
  int? get weightsHashCode => weightsHashCodeNotifier.value;
  set weightsHashCode(int? value) => weightsHashCodeNotifier.value = value;
  
  Object? get lastAreasUpdateHash => lastAreasUpdateHashNotifier.value;
  set lastAreasUpdateHash(Object? value) => lastAreasUpdateHashNotifier.value = value;
  
  int get dragRebuildTrigger => dragRebuildTriggerNotifier.value;
  
  void triggerDragRebuild() {
    dragRebuildTriggerNotifier.value = dragRebuildTriggerNotifier.value + 1;
  }
  
  void dispose() {
    draggingDividerIndexNotifier.dispose();
    hoverDividerIndexNotifier.dispose();
    sizesCacheNotifier.dispose();
    weightsHashCodeNotifier.dispose();
    lastAreasUpdateHashNotifier.dispose();
    dragRebuildTriggerNotifier.dispose();
  }
}
