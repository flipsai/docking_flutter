import 'package:docking/src/drag_over_position.dart';
import 'package:docking/src/internal/widgets/docking_item_widget.dart';
import 'package:docking/src/internal/widgets/docking_tabs_widget.dart';
import 'package:docking/src/layout/docking_layout.dart';
import 'package:docking/src/on_item_close.dart';
import 'package:docking/src/on_item_selection.dart';
import 'package:docking/src/docking_buttons_builder.dart';
import 'package:flutter/material.dart';
import 'package:flutter/widgets.dart';
import 'dart:math' as math;
import 'package:multi_split_view/multi_split_view.dart';
import 'package:tabbed_view/tabbed_view.dart';
import 'package:watch_it/watch_it.dart';
import 'package:get_it/get_it.dart';

/// Callback function type for when a DockingArea's dimensions change.
typedef OnAreaDimensionsChange = void Function(DockingArea area);

/// State management for Docking using ValueNotifiers
class DockingState {
  final ValueNotifier<int> rebuildTriggerNotifier = ValueNotifier<int>(0);
  
  int get rebuildTrigger => rebuildTriggerNotifier.value;
  
  void triggerRebuild() {
    rebuildTriggerNotifier.value = rebuildTriggerNotifier.value + 1;
  }
  
  void dispose() {
    rebuildTriggerNotifier.dispose();
  }
}

/// A StatelessWidget that uses ValueListenableBuilder to potentially react to changes
/// related to a specific DockingArea, if a suitable ValueListenable is provided.
class _AreaWatcher extends StatelessWidget {
  const _AreaWatcher({
    Key? key,
    required this.area,
    required this.child,
    // Optional: Pass a real ValueListenable later if DockingArea exposes one
    // this.listenable,
  }) : super(key: key);

  final DockingArea area;
  final Widget child;
  // final ValueListenable? listenable;

  // Placeholder notifier for the builder structure
  static final _placeholderNotifier = ValueNotifier<int>(0);

  @override
  Widget build(BuildContext context) {
    // Use ValueListenableBuilder listening to a placeholder.
    // Replace `_placeholderNotifier` with a real listenable related to `area` when available.
    return ValueListenableBuilder<int>(
      valueListenable: _placeholderNotifier, // Use placeholder for now
      builder: (context, _, builtChild) {
        // The actual widget representing the area
        return builtChild!;
      },
      child: child, // Pass the original child here
    );
  }
}

/// The docking widget.
class Docking extends StatelessWidget with WatchItMixin {
  Docking({
    Key? key,
    this.layout,
    this.onItemSelection,
    this.onItemClose,
    this.itemCloseInterceptor,
    this.dockingButtonsBuilder,
    this.maximizableItem = true,
    this.maximizableTab = true,
    this.maximizableTabsArea = true,
    this.antiAliasingWorkaround = true,
    this.draggable = true,
    this.onAreaDimensionsChange,
    this.diInstance,
  }) : super(key: key) {
    // Register state management in DI if not already registered
    final di = diInstance ?? GetIt.instance;
    if (!di.isRegistered<DockingState>()) {
      di.registerSingleton<DockingState>(DockingState());
    }
  }

  final DockingLayout? layout;
  final OnItemSelection? onItemSelection;
  final OnItemClose? onItemClose;
  final ItemCloseInterceptor? itemCloseInterceptor;
  final DockingButtonsBuilder? dockingButtonsBuilder;
  final bool maximizableItem;
  final bool maximizableTab;
  final bool maximizableTabsArea;
  final bool antiAliasingWorkaround;
  final bool draggable;
  final OnAreaDimensionsChange? onAreaDimensionsChange;
  final dynamic diInstance;

  @override
  Widget build(BuildContext context) {
    // Get state from DI and watch for changes
    final di = diInstance ?? GetIt.instance;
    final state = di<DockingState>();
    final rebuildTrigger = watchValue((DockingState s) => s.rebuildTriggerNotifier);
    
    final dragOverPosition = DragOverPosition();
    
    if (layout?.root != null) {
      final Widget child = _buildArea(layout!.root!, dragOverPosition);
      if (layout!.maximizedArea != null) {
        List<DockingArea> areas = layout!.layoutAreas();
        List<Widget> children = [];
        for (DockingArea area in areas) {
          if (area != layout!.maximizedArea!) {
            if (area is DockingItem &&
                area.globalKey != null &&
                area.parent != layout!.maximizedArea) {
              // keeping alive other areas
              children.add(ExcludeFocus(
                  child: Offstage(
                      offstage: true,
                      child: TickerMode(
                          enabled: false,
                          child: Builder(builder: (context) {
                            return _buildArea(area, dragOverPosition);
                          })))));
            }
          }
        }
        children.add(child);
        return Stack(children: children);
      }
      return child;
    }
    return Container();
  }

  Widget _buildArea(DockingArea area, DragOverPosition dragOverPosition) {
    Widget actualBuiltWidget;
    if (area is DockingItem) {
      actualBuiltWidget = DockingItemWidget(
          key: area.key,
          layout: layout!,
          dragOverPosition: dragOverPosition,
          draggable: draggable,
          item: area,
          onItemSelection: onItemSelection,
          itemCloseInterceptor: itemCloseInterceptor,
          onItemClose: onItemClose,
          dockingButtonsBuilder: dockingButtonsBuilder,
          maximizable: maximizableItem);
    } else if (area is DockingRow) {
      actualBuiltWidget = _row(area);
    } else if (area is DockingColumn) {
      actualBuiltWidget = _column(area);
    } else if (area is DockingTabs) {
      if (area.childrenCount == 1) {
        actualBuiltWidget = DockingItemWidget(
            key: area.key,
            layout: layout!,
            dragOverPosition: dragOverPosition,
            draggable: draggable,
            item: area.childAt(0),
            onItemSelection: onItemSelection,
            itemCloseInterceptor: itemCloseInterceptor,
            onItemClose: onItemClose,
            dockingButtonsBuilder: dockingButtonsBuilder,
            maximizable: maximizableItem);
      } else {
        actualBuiltWidget = DockingTabsWidget(
            key: area.key,
            layout: layout!,
            dragOverPosition: dragOverPosition,
            draggable: draggable,
            dockingTabs: area,
            onItemSelection: onItemSelection,
            onItemClose: onItemClose,
            itemCloseInterceptor: itemCloseInterceptor,
            dockingButtonsBuilder: dockingButtonsBuilder,
            maximizableTab: maximizableTab,
            maximizableTabsArea: maximizableTabsArea);
      }
    } else {
      throw UnimplementedError('Area not supported: ${area.runtimeType}');
    }
    return _AreaWatcher(area: area, child: actualBuiltWidget);
  }

  Widget _row(DockingRow row) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return _ReactiveMultiSplitView(
          axis: Axis.horizontal,
          controller: _buildController(row),
          onWeightChange: () =>
              _updateAreaDimensions(row, constraints, Axis.horizontal),
          children: _buildDockingChildren(row),
          diInstance: diInstance,
        );
      },
    );
  }

  Widget _column(DockingColumn column) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return _ReactiveMultiSplitView(
          axis: Axis.vertical,
          controller: _buildController(column),
          onWeightChange: () =>
              _updateAreaDimensions(column, constraints, Axis.vertical),
          children: _buildDockingChildren(column),
          diInstance: diInstance,
        );
      },
    );
  }

  MultiSplitViewController _buildController(DockingParentArea area) {
    if (area is DockingRow) {
      return area.controller;
    } else if (area is DockingColumn) {
      return area.controller;
    } else {
      throw UnimplementedError(
          'Unsupported area type for controller: ${area.runtimeType}');
    }
  }

  List<Widget> _buildDockingChildren(DockingParentArea parent) {
    List<Widget> widgets = [];
    for (int i = 0; i < parent.childrenCount; i++) {
      try {
        widgets.add(_buildArea(parent.childAt(i), DragOverPosition()));
      } catch (e) {
        print("Error building child widget at index $i: $e");
      }
    }
    return widgets;
  }

  void _forceRebuild() {
    // Use reactive state management instead of setState
    final di = diInstance ?? GetIt.instance;
    final state = di<DockingState>();
    state.triggerRebuild();
  }

  /// Updates the pixel dimensions of child areas after a resize.
  void _updateAreaDimensions(
      DockingParentArea parentArea, BoxConstraints constraints, Axis axis) {
    final MultiSplitViewController controller = _buildController(parentArea);
    final List<Area> areas = controller.areas.toList();
    final List<double> weights = areas.map((a) => a.weight ?? 0.0).toList();
    final double totalWeight = weights.fold(0.0, (sum, w) => sum + w);

    final double availableSpace = (axis == Axis.horizontal
        ? constraints.maxWidth
        : constraints.maxHeight);

    if (totalWeight <= 0 ||
        availableSpace <= 0 ||
        areas.length != parentArea.childrenCount) {
      print(
          "Skipping dimension update: totalWeight=$totalWeight, availableSpace=$availableSpace, areaCount=${areas.length}, dockingChildCount=${parentArea.childrenCount}");
      return;
    }

    for (int i = 0; i < areas.length; i++) {
      final Area area = areas[i];
      DockingArea dockingArea;
      try {
        dockingArea = parentArea.childAt(i);
      } catch (e) {
        print("Error getting DockingArea child at index $i: $e");
        continue;
      }

      final double childWeight = weights[i];
      final double proportion = childWeight / totalWeight;
      double childDimension = availableSpace * proportion;

      childDimension = math.max(0, childDimension);

      double? newWidth = axis == Axis.horizontal ? childDimension : null;
      double? newHeight = axis == Axis.vertical ? childDimension : null;

      if (axis == Axis.horizontal && newWidth != null) {
        newHeight = constraints.hasBoundedHeight
            ? constraints.maxHeight
            : dockingArea.height;
      } else if (axis == Axis.vertical && newHeight != null) {
        newWidth = constraints.hasBoundedWidth
            ? constraints.maxWidth
            : dockingArea.width;
      }

      // Update the Area object's primary size for MultiSplitView layout
      area.updateSize(childDimension);

      // Update the width/height properties on the Area/DockingArea for persistence
      // (updateDimensions now only sets width/height)
      dockingArea.updateDimensions(newWidth, newHeight);

      // Trigger the callback to notify listeners (like the main app)
      onAreaDimensionsChange?.call(dockingArea);
    }

    _forceRebuild();
  }
}

/// Reactive wrapper for MultiSplitView that uses dependency injection for state management
class _ReactiveMultiSplitView extends StatelessWidget {
  const _ReactiveMultiSplitView({
    Key? key,
    required this.axis,
    required this.controller,
    required this.onWeightChange,
    required this.children,
    this.diInstance,
  }) : super(key: key);

  final Axis axis;
  final MultiSplitViewController controller;
  final VoidCallback onWeightChange;
  final List<Widget> children;
  final dynamic diInstance;

  @override
  Widget build(BuildContext context) {
    // Use the reactive MultiSplitView with DI
    return MultiSplitView(
      axis: axis,
      controller: controller,
      onWeightChange: onWeightChange,
      children: children,
      diInstance: diInstance,
    );
  }
}
