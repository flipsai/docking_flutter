import 'package:docking/docking.dart';
import 'package:docking/src/drag_over_position.dart';
import 'package:docking/src/internal/widgets/docking_item_widget.dart';
import 'package:docking/src/internal/widgets/docking_tabs_widget.dart';
import 'package:flutter/material.dart';
import 'package:flutter/widgets.dart';
import 'dart:math' as math;

/// Callback function type for when a DockingArea's dimensions change.
typedef OnAreaDimensionsChange = void Function(DockingArea area);

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
class Docking extends StatefulWidget {
  const Docking(
      {Key? key,
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
      })
      : super(key: key);

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

  @override
  State<StatefulWidget> createState() => _DockingState();
}

/// The [Docking] state.
class _DockingState extends State<Docking> {
  final DragOverPosition _dragOverPosition = DragOverPosition();

  @override
  void initState() {
    super.initState();
    _dragOverPosition.addListener(_forceRebuild);
    widget.layout?.addListener(_forceRebuild);
  }

  @override
  void dispose() {
    super.dispose();
    _dragOverPosition.removeListener(_forceRebuild);
    widget.layout?.removeListener(_forceRebuild);
  }

  @override
  void didUpdateWidget(Docking oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.layout != widget.layout) {
      oldWidget.layout?.removeListener(_forceRebuild);
      widget.layout?.addListener(_forceRebuild);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.layout?.root != null) {
      final Widget child = _buildArea(widget.layout!.root!);
      if (widget.layout!.maximizedArea != null) {
        List<DockingArea> areas = widget.layout!.layoutAreas();
        List<Widget> children = [];
        for (DockingArea area in areas) {
          if (area != widget.layout!.maximizedArea!) {
            if (area is DockingItem &&
                area.globalKey != null &&
                area.parent != widget.layout!.maximizedArea) {
              // keeping alive other areas
              children.add(ExcludeFocus(
                  child: Offstage(
                      offstage: true,
                      child: TickerMode(
                          enabled: false,
                          child: Builder(builder: (context) {
                            return _buildArea(area);
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

  Widget _buildArea(DockingArea area) {
    Widget actualBuiltWidget;
    if (area is DockingItem) {
      actualBuiltWidget = DockingItemWidget(
          key: area.key,
          layout: widget.layout!,
          dragOverPosition: _dragOverPosition,
          draggable: widget.draggable,
          item: area,
          onItemSelection: widget.onItemSelection,
          itemCloseInterceptor: widget.itemCloseInterceptor,
          onItemClose: widget.onItemClose,
          dockingButtonsBuilder: widget.dockingButtonsBuilder,
          maximizable: widget.maximizableItem);
    } else if (area is DockingRow) {
      actualBuiltWidget = _row(area);
    } else if (area is DockingColumn) {
      actualBuiltWidget = _column(area);
    } else if (area is DockingTabs) {
      if (area.childrenCount == 1 && area.childAt(0) is DockingItem) {
        actualBuiltWidget = DockingItemWidget(
            key: area.key,
            layout: widget.layout!,
            dragOverPosition: _dragOverPosition,
            draggable: widget.draggable,
            item: area.childAt(0) as DockingItem,
            onItemSelection: widget.onItemSelection,
            itemCloseInterceptor: widget.itemCloseInterceptor,
            onItemClose: widget.onItemClose,
            dockingButtonsBuilder: widget.dockingButtonsBuilder,
            maximizable: widget.maximizableItem);
      } else {
        actualBuiltWidget = DockingTabsWidget(
            key: area.key,
            layout: widget.layout!,
            dragOverPosition: _dragOverPosition,
            draggable: widget.draggable,
            dockingTabs: area,
            onItemSelection: widget.onItemSelection,
            onItemClose: widget.onItemClose,
            itemCloseInterceptor: widget.itemCloseInterceptor,
            dockingButtonsBuilder: widget.dockingButtonsBuilder,
            maximizableTab: widget.maximizableTab,
            maximizableTabsArea: widget.maximizableTabsArea);
      }
    } else {
      throw UnimplementedError('Area not supported: ${area.runtimeType}');
    }
    return _AreaWatcher(area: area, child: actualBuiltWidget);
  }

  Widget _row(DockingRow row) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return MultiSplitView(
          axis: Axis.horizontal,
          controller: _buildController(row),
          onWeightChange: () => _updateAreaDimensions(row, constraints, Axis.horizontal),
          children: _buildDockingChildren(row),
        );
      },
    );
  }

  Widget _column(DockingColumn column) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return MultiSplitView(
          axis: Axis.vertical,
          controller: _buildController(column),
          onWeightChange: () => _updateAreaDimensions(column, constraints, Axis.vertical),
          children: _buildDockingChildren(column),
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
      throw UnimplementedError('Unsupported area type for controller: ${area.runtimeType}');
    }
  }

  List<Widget> _buildDockingChildren(DockingParentArea parent) {
    List<Widget> widgets = [];
    for (int i = 0; i < parent.childrenCount; i++) {
      try {
        widgets.add(_buildArea(parent.childAt(i)));
      } catch (e) {
        print("Error building child widget at index $i: $e");
      }
    }
    return widgets;
  }

  void _forceRebuild() {
    setState(() {
      // just rebuild
    });
  }

  /// Updates the pixel dimensions of child areas after a resize.
  void _updateAreaDimensions(DockingParentArea parentArea, BoxConstraints constraints, Axis axis) {
    final MultiSplitViewController controller = _buildController(parentArea);
    final List<Area> areas = controller.areas.toList();
    final List<double> weights = areas.map((a) => a.weight ?? 0.0).toList();
    final double totalWeight = weights.fold(0.0, (sum, w) => sum + w);
    
    final double availableSpace = (axis == Axis.horizontal ? constraints.maxWidth : constraints.maxHeight);

    if (totalWeight <= 0 || availableSpace <= 0 || areas.length != parentArea.childrenCount) {
        print("Skipping dimension update: totalWeight=$totalWeight, availableSpace=$availableSpace, areaCount=${areas.length}, dockingChildCount=${parentArea.childrenCount}");
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
          newHeight = constraints.hasBoundedHeight ? constraints.maxHeight : dockingArea.height;
      } else if (axis == Axis.vertical && newHeight != null) {
          newWidth = constraints.hasBoundedWidth ? constraints.maxWidth : dockingArea.width;
      }

      // Update the Area object's primary size for MultiSplitView layout
      area.updateSize(childDimension);
      
      // Update the width/height properties on the Area/DockingArea for persistence 
      // (updateDimensions now only sets width/height)
      dockingArea.updateDimensions(newWidth, newHeight);
      
      // Trigger the callback to notify listeners (like the main app)
      widget.onAreaDimensionsChange?.call(dockingArea);
    }

    _forceRebuild();
  }
}
