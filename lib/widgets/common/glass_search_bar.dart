import 'package:flutter/material.dart';
import 'package:flick/core/theme/app_colors.dart';
import 'package:flick/core/constants/app_constants.dart';
import 'package:flick/core/theme/adaptive_color_provider.dart';
import 'package:flick/widgets/common/glassmorphism_container.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

/// A reusable search bar widget applying the glassmorphism design language.
class GlassSearchBar extends StatefulWidget {
  /// The controller for the search text field
  final TextEditingController controller;

  /// Callback when the search text changes
  final ValueChanged<String>? onChanged;

  /// Hint text to display when the search bar is empty
  final String hintText;

  /// Callback when the search bar is cleared via the clear button
  final VoidCallback? onClear;

  /// Whether to show the glass background (default: true)
  final bool showBackground;

  /// Optional focus node for external focus control (e.g. autoFocusSearch).
  final FocusNode? focusNode;

  /// Whether to autofocus the field.
  final bool autofocus;

  /// Text input action for keyboard.
  final TextInputAction? textInputAction;

  const GlassSearchBar({
    super.key,
    required this.controller,
    this.onChanged,
    this.hintText = 'Search...',
    this.onClear,
    this.showBackground = true,
    this.focusNode,
    this.autofocus = false,
    this.textInputAction,
  });

  @override
  State<GlassSearchBar> createState() => _GlassSearchBarState();
}

class _GlassSearchBarState extends State<GlassSearchBar> {
  bool _showClearButton = false;
  FocusNode? _ownedFocusNode;
  bool _hadFocus = false;
  bool _pendingSelectAllOnTap = false;

  FocusNode get _focusNode => widget.focusNode ?? (_ownedFocusNode ??= FocusNode());

  @override
  void initState() {
    super.initState();
    _showClearButton = widget.controller.text.isNotEmpty;
    widget.controller.addListener(_onTextChanged);
    _hadFocus = _focusNode.hasFocus;
    _focusNode.addListener(_onFocusChanged);
  }

  @override
  void didUpdateWidget(covariant GlassSearchBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onTextChanged);
      widget.controller.addListener(_onTextChanged);
      _showClearButton = widget.controller.text.isNotEmpty;
    }
    if (oldWidget.focusNode != widget.focusNode) {
      (oldWidget.focusNode ?? _ownedFocusNode)?.removeListener(_onFocusChanged);
      if (widget.focusNode != null) {
        _ownedFocusNode?.dispose();
        _ownedFocusNode = null;
      }
      _hadFocus = _focusNode.hasFocus;
      _focusNode.addListener(_onFocusChanged);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onTextChanged);
    (widget.focusNode ?? _ownedFocusNode)?.removeListener(_onFocusChanged);
    _ownedFocusNode?.dispose();
    super.dispose();
  }

  void _selectAll() {
    final text = widget.controller.text;
    if (text.isEmpty) return;
    widget.controller.selection = TextSelection(
      baseOffset: 0,
      extentOffset: text.length,
    );
  }

  void _onFocusChanged() {
    final hasFocus = _focusNode.hasFocus;
    if (hasFocus && !_hadFocus) {
      if (widget.controller.text.isNotEmpty) {
        _selectAll();
        _pendingSelectAllOnTap = true;
      }
    } else if (!hasFocus) {
      _pendingSelectAllOnTap = false;
    }
    _hadFocus = hasFocus;
  }

  void _onTap() {
    if (!_pendingSelectAllOnTap) return;
    _pendingSelectAllOnTap = false;
    _selectAll();
  }

  void _onTextChanged() {
    final showClear = widget.controller.text.isNotEmpty;
    if (_showClearButton != showClear) {
      if (mounted) {
        setState(() {
          _showClearButton = showClear;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final content = Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppConstants.spacingMd,
        vertical: AppConstants.spacingSm,
      ),
      child: Row(
        children: [
          Icon(
            LucideIcons.search,
            color: context.adaptiveTextSecondary,
            size: AppConstants.iconSizeMd,
          ),
          const SizedBox(width: AppConstants.spacingSm),
          Expanded(
            child: TextField(
              controller: widget.controller,
              focusNode: _focusNode,
              autofocus: widget.autofocus,
              textInputAction: widget.textInputAction,
              onTap: _onTap,
              onChanged: (value) {
                _pendingSelectAllOnTap = false;
                widget.onChanged?.call(value);
              },
              onTapOutside: (_) => FocusScope.of(context).unfocus(),
              style: TextStyle(
                color: context.adaptiveTextPrimary,
                fontSize: 16,
              ),
              decoration: InputDecoration(
                hintText: widget.hintText,
                hintStyle: TextStyle(color: context.adaptiveTextTertiary),
                border: InputBorder.none,
                isDense: true,
                contentPadding: EdgeInsets.zero,
              ),
              cursorColor: AppColors.accent,
            ),
          ),
          if (_showClearButton)
            GestureDetector(
              onTap: () {
                _pendingSelectAllOnTap = false;
                widget.controller.clear();
                widget.onChanged?.call('');
                widget.onClear?.call();
              },
              behavior: HitTestBehavior.opaque,
              child: Padding(
                padding: const EdgeInsets.only(left: AppConstants.spacingSm),
                child: Icon(
                  LucideIcons.x,
                  color: context.adaptiveTextSecondary,
                  size: AppConstants.iconSizeMd,
                ),
              ),
            ),
        ],
      ),
    );

    if (widget.showBackground) {
      return GlassmorphismContainer(
        padding: EdgeInsets.zero,
        borderRadius: BorderRadius.circular(AppConstants.radiusXl),
        child: content,
      );
    }

    return content;
  }
}
