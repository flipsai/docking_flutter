import 'package:docking/src/drag_over_position.dart';
import 'package:docking/src/layout/docking_layout.dart';
import 'package:flutter/material.dart';
import 'package:meta/meta.dart';
import 'package:tabbed_view/tabbed_view.dart';

/// Represents a draggable widget mixin.
@internal
mixin DraggableConfigMixin {
  DraggableConfig buildDraggableConfig(
      {required DragOverPosition dockingDrag, required TabData tabData}) {
    DockingItem item = tabData.value;
    String name = item.name != null ? item.name! : '';
    return DraggableConfig(
        feedback: buildFeedback(name),
        dragAnchorStrategy: (Draggable<Object> draggable, BuildContext context,
                Offset position) =>
            Offset(20, 20),
        onDragStarted: () {
          dockingDrag.enable = true;
        },
        onDragCompleted: () {
          dockingDrag.enable = false;
        });
  }

  Widget buildFeedback(String name) {
    return Material(
        child: Container(
            decoration:
                BoxDecoration(border: Border.all(), color: Colors.grey[300]),
            child: ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight: 0,
                  minWidth: 30,
                  maxHeight: double.infinity,
                  maxWidth: 150.0,
                ),
                child: Padding(
                    padding: EdgeInsets.all(4),
                    child: Text(name, overflow: TextOverflow.ellipsis)))));
  }
}
