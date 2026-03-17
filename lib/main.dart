import 'dart:convert';
import 'dart:ui';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:math_expressions/math_expressions.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'package:file_picker/file_picker.dart';
import 'package:share_plus/share_plus.dart';

void main() {
  runApp(const CalcApp());
}

// ---------------------------------------------------------------------------
// 1. ROOT APP: THEME & BRAND ENGINE
// ---------------------------------------------------------------------------
class CalcApp extends StatefulWidget {
  const CalcApp({super.key});

  @override
  State<CalcApp> createState() => _CalcAppState();
}

class _CalcAppState extends State<CalcApp> {
  ThemeMode _themeMode = ThemeMode.light;
  Color _seedColor = Colors.cyanAccent; // The signature 'Pro' cyan

  void changeTheme(ThemeMode mode, Color seed) {
    setState(() {
      _themeMode = mode;
      _seedColor = seed;
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Calc', // Technical app title
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.light,
        colorScheme: ColorScheme.fromSeed(
          seedColor: _seedColor,
          brightness: Brightness.light,
        ),
        scaffoldBackgroundColor: const Color(0xFFF0F2F5),
        fontFamily: 'Roboto',
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorScheme: ColorScheme.fromSeed(
          seedColor: _seedColor,
          brightness: Brightness.dark,
        ),
        scaffoldBackgroundColor: const Color(0xFF0D0D0D),
        fontFamily: 'Roboto',
      ),
      themeMode: _themeMode,
      home: HomeScreen(
        onThemeChanged: changeTheme,
        currentMode: _themeMode,
        currentSeed: _seedColor,
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 2. DATA MODELS
// ---------------------------------------------------------------------------
class HistoryItem {
  final String action;
  final String result;
  final DateTime time;
  final Color? custColor;
  HistoryItem({
    required this.action,
    required this.result,
    required this.time,
    this.custColor,
  });
}

class CalcSession {
  String history;
  TextEditingController controller;
  Color color;
  CalcSession({
    required this.history,
    required this.controller,
    required this.color,
  });
}

class ProductItem {
  final String name;
  final double price;
  ProductItem({required this.name, required this.price});

  Map<String, dynamic> toJson() => {'name': name, 'price': price};
  factory ProductItem.fromJson(Map<String, dynamic> json) {
    return ProductItem(name: json['name'], price: json['price']);
  }
}

// ---------------------------------------------------------------------------
// 3. MAIN APP SHELL (NAV & UX OPTIMIZATION)
// ---------------------------------------------------------------------------
class HomeScreen extends StatefulWidget {
  final Function(ThemeMode, Color) onThemeChanged;
  final ThemeMode currentMode;
  final Color currentSeed;
  const HomeScreen({
    super.key,
    required this.onThemeChanged,
    required this.currentMode,
    required this.currentSeed,
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _currentIndex = 0;
  final GlobalKey<_CalculatorTabState> _calcKey = GlobalKey();

  void _sendToCalculator(String value) {
    setState(() => _currentIndex = 0);
    Future.delayed(const Duration(milliseconds: 150), () {
      _calcKey.currentState?.appendFromExternal(value);
    });
  }

  @override
  Widget build(BuildContext context) {
    // UX FIX: Tapping blank space hides keyboard across all tabs
    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: Scaffold(
        body: IndexedStack(
          index: _currentIndex,
          children: [
            CalculatorTab(
              key: _calcKey,
              onThemeChanged: widget.onThemeChanged,
              currentMode: widget.currentMode,
              currentSeed: widget.currentSeed,
            ),
            CurrencyTab(onSendToCalc: _sendToCalculator),
            PriceBookTab(onSendToCalc: _sendToCalculator),
          ],
        ),
        bottomNavigationBar: BottomNavigationBar(
          currentIndex: _currentIndex,
          onTap: (index) {
            HapticFeedback.selectionClick();
            setState(() => _currentIndex = index);
          },
          backgroundColor: Theme.of(context).colorScheme.surface,
          selectedItemColor: Theme.of(context).colorScheme.primary,
          unselectedItemColor: Theme.of(
            context,
          ).colorScheme.onSurfaceVariant.withOpacity(0.5),
          showUnselectedLabels: true,
          type: BottomNavigationBarType.fixed,
          items: const [
            BottomNavigationBarItem(
              icon: Icon(Icons.calculate),
              label: "Calculator",
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.currency_exchange),
              label: "Currency",
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.menu_book),
              label: "Price Book",
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 4. TAB 1: CALCULATOR CORE (MATH & LAG OPTIMIZATION)
// ---------------------------------------------------------------------------
class CalculatorTab extends StatefulWidget {
  final Function(ThemeMode, Color) onThemeChanged;
  final ThemeMode currentMode;
  final Color currentSeed;
  const CalculatorTab({
    super.key,
    required this.onThemeChanged,
    required this.currentMode,
    required this.currentSeed,
  });

  @override
  State<CalculatorTab> createState() => _CalculatorTabState();
}

class _CalculatorTabState extends State<CalculatorTab> {
  bool _isMultiUserMode = false;
  bool _isReverseMode = false;
  bool _isExpanded = false;

  int _activeTabIndex = 0;
  String _liveResult = "";

  final List<HistoryItem> _globalHistory = [];
  final List<CalcSession> _sessions = [
    CalcSession(
      history: "",
      controller: TextEditingController(),
      color: const Color(0xFFFF6B6B),
    ),
    CalcSession(
      history: "",
      controller: TextEditingController(),
      color: const Color(0xFF69F0AE),
    ),
    CalcSession(
      history: "",
      controller: TextEditingController(),
      color: const Color(0xFF7C4DFF),
    ),
  ];

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  void appendFromExternal(String val) {
    setState(() {
      var current = _sessions[_activeTabIndex];
      var controller = current.controller;
      String text = controller.text;

      if (text.isEmpty ||
          text.endsWith('+') ||
          text.endsWith('-') ||
          text.endsWith('*') ||
          text.endsWith('/')) {
        controller.text = text + val;
      } else {
        controller.text = "$text + $val";
      }
      controller.selection = TextSelection.collapsed(
        offset: controller.text.length,
      );
      _updateLivePreview();
    });
    _saveData();
  }

  Future<void> _saveData() async {
    final prefs = await SharedPreferences.getInstance();
    final String encodedHistory = jsonEncode(
      _globalHistory
          .map(
            (item) => {
              'action': item.action,
              'result': item.result,
              'time': item.time.toIso8601String(),
              'color': item.custColor?.value,
            },
          )
          .toList(),
    );
    await prefs.setString('vyapar_history', encodedHistory);
    for (int i = 0; i < 3; i++) {
      await prefs.setString('session_input_$i', _sessions[i].controller.text);
      await prefs.setString('session_history_$i', _sessions[i].history);
    }
    await prefs.setInt('active_tab', _activeTabIndex);
    await prefs.setBool('multi_user', _isMultiUserMode);
  }

  Future<void> _loadData() async {
    final prefs = await SharedPreferences.getInstance();
    final String? historyString = prefs.getString('vyapar_history');
    if (historyString != null) {
      final List<dynamic> decoded = jsonDecode(historyString);
      setState(() {
        _globalHistory.clear();
        _globalHistory.addAll(
          decoded.map(
            (x) => HistoryItem(
              action: x['action'],
              result: x['result'],
              time: DateTime.parse(x['time']),
              custColor: x['color'] != null ? Color(x['color']) : null,
            ),
          ),
        );
      });
    }
    setState(() {
      for (int i = 0; i < 3; i++) {
        String? savedInput = prefs.getString('session_input_$i');
        String? savedHistory = prefs.getString('session_history_$i');
        if (savedInput != null) _sessions[i].controller.text = savedInput;
        if (savedHistory != null) _sessions[i].history = savedHistory;
      }
      _activeTabIndex = prefs.getInt('active_tab') ?? 0;
      _isMultiUserMode = prefs.getBool('multi_user') ?? false;
    });
  }

  void _addToHistory(String action, String result, Color color) {
    setState(() {
      _globalHistory.insert(
        0,
        HistoryItem(
          action: action,
          result: result,
          time: DateTime.now(),
          custColor: color,
        ),
      );
      if (_globalHistory.length > 50) _globalHistory.removeLast();
    });
    _saveData();
  }

  String _parseGSTString(String input) {
    bool changed = true;
    String processed = input;
    while (changed) {
      String next = processed.replaceFirstMapped(
        RegExp(r'(.*?)\s*\+\s*([\d.]+)%'),
        (m) => '(${m.group(1)}) * (1 + (${m.group(2)} / 100))',
      );
      if (next == processed) {
        next = processed.replaceFirstMapped(
          RegExp(r'(.*?)\s*-\s*([\d.]+)%'),
          (m) => '(${m.group(1)}) / (1 + (${m.group(2)} / 100))',
        );
      }
      if (next == processed) changed = false;
      processed = next;
    }
    return processed
        .replaceAll('x', '*')
        .replaceAll('÷', '/')
        .replaceAll('%', '/100');
  }

  void _updateLivePreview() {
    String input = _sessions[_activeTabIndex].controller.text;
    String parsedInput = _parseGSTString(input);

    if (parsedInput.isEmpty ||
        "+-*/(".contains(parsedInput[parsedInput.length - 1])) {
      setState(() => _liveResult = "");
      return;
    }
    try {
      Parser p = Parser();
      Expression exp = p.parse(parsedInput);
      ContextModel cm = ContextModel();
      double eval = exp.evaluate(EvaluationType.REAL, cm);

      // BUG FIX: Prevent Divide by Zero Lag/Crash in preview
      if (eval.isInfinite || eval.isNaN) {
        setState(() => _liveResult = "Error");
        return;
      }

      setState(
        () => _liveResult = eval % 1 == 0
            ? eval.toStringAsFixed(0)
            : eval.toStringAsFixed(2),
      );
    } catch (e) {
      setState(() => _liveResult = "");
    }
  }

  void _calculateResult(CalcSession session) {
    try {
      String input = session.controller.text;
      if (input.isEmpty) return;
      String originalInput = input;
      String parsedInput = _parseGSTString(input);

      int open = '('.allMatches(parsedInput).length;
      int close = ')'.allMatches(parsedInput).length;
      if (open > close) parsedInput += ')' * (open - close);

      Parser p = Parser();
      Expression exp = p.parse(parsedInput);
      ContextModel cm = ContextModel();
      double eval = exp.evaluate(EvaluationType.REAL, cm);

      // BUG FIX: Prevent Divide by Zero Crash on equals
      if (eval.isInfinite || eval.isNaN) {
        setState(() => _liveResult = "Error");
        return;
      }

      String resultStr = eval % 1 == 0
          ? eval.toStringAsFixed(0)
          : eval.toStringAsFixed(2);

      _addToHistory(originalInput, resultStr, session.color);
      session.history = session.controller.text;
      session.controller.text = resultStr;
      session.controller.selection = TextSelection.collapsed(
        offset: resultStr.length,
      );

      setState(() => _liveResult = "");
    } catch (e) {
      setState(() => _liveResult = "Error");
    }
  }

  void _applyGST(double rate) {
    HapticFeedback.mediumImpact();
    setState(() {
      var current = _sessions[_activeTabIndex];
      _calculateResult(current);

      String text = current.controller.text;
      if (text.isEmpty || rate == 0) return;

      String rateStr = rate % 1 == 0
          ? rate.toStringAsFixed(0)
          : rate.toStringAsFixed(2);
      if (_isReverseMode) {
        current.controller.text = "$text - $rateStr%";
      } else {
        current.controller.text = "$text + $rateStr%";
      }
      current.controller.selection = TextSelection.collapsed(
        offset: current.controller.text.length,
      );
      _updateLivePreview();
    });
    _saveData();
  }

  void _onBtn(String val) {
    HapticFeedback.lightImpact();
    setState(() {
      var current = _sessions[_activeTabIndex];
      var controller = current.controller;
      int cursorPos = controller.selection.base.offset;
      if (cursorPos < 0) cursorPos = controller.text.length;
      String text = controller.text;

      if (val == "C") {
        controller.clear();
        current.history = "";
        _liveResult = "";
        _saveData(); // Save on clear
      } else if (val == "⌫") {
        if (text.isNotEmpty) {
          if (controller.selection.start != controller.selection.end) {
            String newText = text.replaceRange(
              controller.selection.start,
              controller.selection.end,
              "",
            );
            controller.value = TextEditingValue(
              text: newText,
              selection: TextSelection.collapsed(
                offset: controller.selection.start,
              ),
            );
          } else if (cursorPos > 0) {
            String newText =
                text.substring(0, cursorPos - 1) + text.substring(cursorPos);
            controller.value = TextEditingValue(
              text: newText,
              selection: TextSelection.collapsed(offset: cursorPos - 1),
            );
          }
        }
      } else if (val == "=") {
        _calculateResult(current);
        _saveData(); // Save on equals
      } else {
        String newText;
        int newCursorPos;
        if (controller.selection.start != controller.selection.end) {
          newText = text.replaceRange(
            controller.selection.start,
            controller.selection.end,
            val,
          );
          newCursorPos = controller.selection.start + val.length;
        } else {
          newText =
              text.substring(0, cursorPos) + val + text.substring(cursorPos);
          newCursorPos = cursorPos + val.length;
        }
        controller.value = TextEditingValue(
          text: newText,
          selection: TextSelection.collapsed(offset: newCursorPos),
        );
      }
      if (val != "=" && val != "C") _updateLivePreview();

      // LAG FIX: Standard typing no longer triggers heavy disk write (_saveData)
    });
  }

  void _showThemeSettings() {
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      builder: (context) {
        return Container(
          padding: const EdgeInsets.all(20),
          height: 350,
          child: Column(
            children: [
              const Text(
                "Theme Settings",
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 20),
              SegmentedButton<ThemeMode>(
                segments: const [
                  ButtonSegment(
                    value: ThemeMode.light,
                    icon: Icon(Icons.wb_sunny),
                    label: Text("Light"),
                  ),
                  ButtonSegment(
                    value: ThemeMode.dark,
                    icon: Icon(Icons.nights_stay),
                    label: Text("Dark"),
                  ),
                ],
                selected: {widget.currentMode},
                onSelectionChanged: (val) =>
                    widget.onThemeChanged(val.first, widget.currentSeed),
              ),
              const SizedBox(height: 20),
              Wrap(
                spacing: 15,
                runSpacing: 15,
                children:
                    [
                          Colors.cyanAccent,
                          Colors.purpleAccent,
                          Colors.greenAccent,
                          Colors.orangeAccent,
                          const Color(0xFFFF4081),
                        ]
                        .map(
                          (c) => GestureDetector(
                            onTap: () {
                              widget.onThemeChanged(widget.currentMode, c);
                              Navigator.pop(context);
                            },
                            child: CircleAvatar(backgroundColor: c, radius: 20),
                          ),
                        )
                        .toList(),
              ),
            ],
          ),
        );
      },
    );
  }

  void _showHistoryModal() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return SizedBox(
          height: MediaQuery.of(context).size.height * 0.75,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(20),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      "History Ledger",
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete_sweep, color: Colors.red),
                      onPressed: () {
                        setState(() => _globalHistory.clear());
                        _saveData();
                        Navigator.pop(context);
                      },
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView.builder(
                  itemCount: _globalHistory.length,
                  itemBuilder: (ctx, i) {
                    final item = _globalHistory[i];
                    return ListTile(
                      leading: CircleAvatar(
                        backgroundColor: item.custColor,
                        radius: 5,
                      ),
                      title: Text(
                        item.result,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 18,
                        ),
                      ),
                      subtitle: Text(item.action),
                      trailing: Text(
                        "${item.time.hour}:${item.time.minute.toString().padLeft(2, '0')}",
                      ),
                      onTap: () {
                        Navigator.pop(context);
                        setState(
                          () => _sessions[_activeTabIndex].controller.text =
                              item.result,
                        );
                        _updateLivePreview();
                        _saveData();
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildTabButton(int index, String label) {
    bool isActive = _activeTabIndex == index;
    Color color = _sessions[index].color;
    return GestureDetector(
      onTap: () {
        setState(() => _activeTabIndex = index);
        _saveData();
        HapticFeedback.selectionClick();
      },
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: isActive ? color.withOpacity(0.2) : Colors.transparent,
          border: Border.all(color: isActive ? color : Colors.transparent),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          children: [
            Icon(Icons.person, color: isActive ? color : Colors.grey),
            if (_sessions[index].controller.text.isNotEmpty && !isActive)
              Text("..", style: TextStyle(color: color)),
          ],
        ),
      ),
    );
  }

  Widget _gstBtn(
    String label,
    double rate,
    Color userColor, {
    bool isStandard = false,
  }) {
    final scheme = Theme.of(context).colorScheme;
    Color btnColor = _isReverseMode ? scheme.error : userColor;
    return Expanded(
      child: GestureDetector(
        onTap: () => _applyGST(rate),
        child: Container(
          margin: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: isStandard
                ? btnColor.withOpacity(0.15)
                : scheme.surfaceContainerHighest.withOpacity(0.5),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: isStandard
                  ? btnColor.withOpacity(0.5)
                  : Colors.transparent,
            ),
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: TextStyle(
              fontWeight: FontWeight.w600,
              color: isStandard ? btnColor : scheme.onSurfaceVariant,
            ),
          ),
        ),
      ),
    );
  }

  Widget _row(List<String> keys, ColorScheme scheme, {bool isAction = false}) {
    return Expanded(
      child: Row(
        children: keys.map((key) {
          Color txt = scheme.onSurface;
          Color bg = scheme.surfaceContainerHigh;
          if (["C", "⌫"].contains(key)) {
            txt = scheme.error;
            bg = scheme.surfaceContainerHighest;
          }
          if (["÷", "x", "-", "+"].contains(key)) txt = scheme.tertiary;
          if (key == "=") {
            bg = scheme.primary;
            txt = scheme.onPrimary;
          }
          return Expanded(
            child: Container(
              margin: const EdgeInsets.all(4),
              child: InkWell(
                onTap: () => _onBtn(key),
                borderRadius: BorderRadius.circular(18),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 100),
                  decoration: BoxDecoration(
                    color: bg,
                    borderRadius: BorderRadius.circular(18),
                  ),
                  alignment: Alignment.center,
                  child: key == "⌫"
                      ? Icon(Icons.backspace_outlined, color: txt)
                      : Text(
                          key,
                          style: TextStyle(
                            fontSize: 26,
                            fontWeight: FontWeight.w500,
                            color: txt,
                          ),
                        ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    var activeSession = _sessions[_activeTabIndex];
    Color userColor = _isMultiUserMode ? activeSession.color : scheme.primary;

    return SafeArea(
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                IconButton(
                  icon: const Icon(Icons.history),
                  onPressed: _showHistoryModal,
                ),
                // UX FIX: Cleaned up technical text for pro look
                Text(
                  "CALC PRO",
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: scheme.onSurfaceVariant,
                    letterSpacing: 1.5,
                  ),
                ),
                Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.palette_outlined),
                      onPressed: _showThemeSettings,
                    ),
                    Transform.scale(
                      scale: 0.7,
                      child: Switch(
                        value: _isMultiUserMode,
                        onChanged: (v) => setState(() => _isMultiUserMode = v),
                        activeColor: Colors.amber,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Expanded(
            child: Row(
              children: [
                if (_isMultiUserMode)
                  Container(
                    width: 70,
                    color: scheme.surfaceContainerLow,
                    child: Column(
                      children: [
                        _buildTabButton(0, "1"),
                        _buildTabButton(1, "2"),
                        _buildTabButton(2, "3"),
                      ],
                    ),
                  ),
                Expanded(
                  child: Column(
                    children: [
                      Expanded(
                        flex: 4,
                        child: Container(
                          margin: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 4,
                          ),
                          // PERFORMANCE FIX: Replaced BackdropFilter blur with clean translucent solid color to eliminate frame drops on older phones
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(24),
                            color: scheme.surfaceContainerHighest.withOpacity(
                              0.5,
                            ),
                            border: Border.all(
                              color: scheme.outlineVariant.withOpacity(0.3),
                            ),
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(24),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 20,
                                vertical: 10,
                              ),
                              child: SingleChildScrollView(
                                reverse: true,
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.end,
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    Text(
                                      activeSession.history,
                                      style: TextStyle(
                                        color: scheme.onSurfaceVariant,
                                        fontSize: 16,
                                      ),
                                    ),
                                    const SizedBox(height: 5),
                                    TextField(
                                      controller: activeSession.controller,
                                      readOnly: true,
                                      showCursor: true,
                                      autofocus: true,
                                      textAlign: TextAlign.right,
                                      style: TextStyle(
                                        fontSize: 50,
                                        fontWeight: FontWeight.w300,
                                        color: _isMultiUserMode
                                            ? activeSession.color
                                            : scheme.onSurface,
                                      ),
                                      decoration: const InputDecoration(
                                        border: InputBorder.none,
                                        isDense: true,
                                        contentPadding: EdgeInsets.zero,
                                      ),
                                    ),
                                    if (_liveResult.isNotEmpty)
                                      Text(
                                        _liveResult == "Error"
                                            ? _liveResult
                                            : "= $_liveResult",
                                        style: TextStyle(
                                          fontSize: 24,
                                          fontWeight: FontWeight.bold,
                                          color: _liveResult == "Error"
                                              ? scheme.error
                                              : scheme.primary.withOpacity(0.5),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 4,
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            InkWell(
                              onTap: () {
                                HapticFeedback.mediumImpact();
                                setState(() => _isExpanded = !_isExpanded);
                              },
                              borderRadius: BorderRadius.circular(12),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 8,
                                ),
                                decoration: BoxDecoration(
                                  color: _isExpanded
                                      ? scheme.primary.withOpacity(0.2)
                                      : scheme.surfaceContainerHighest,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Row(
                                  children: [
                                    Icon(
                                      _isExpanded
                                          ? Icons.close_fullscreen
                                          : Icons.open_in_full,
                                      size: 18,
                                      color: _isExpanded
                                          ? scheme.primary
                                          : scheme.onSurfaceVariant,
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      "GST PANEL",
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        color: _isExpanded
                                            ? scheme.primary
                                            : scheme.onSurfaceVariant,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            InkWell(
                              onTap: () {
                                HapticFeedback.selectionClick();
                                setState(
                                  () => _isReverseMode = !_isReverseMode,
                                );
                              },
                              borderRadius: BorderRadius.circular(12),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 8,
                                ),
                                decoration: BoxDecoration(
                                  color: _isReverseMode
                                      ? scheme.errorContainer
                                      : scheme.tertiaryContainer,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Text(
                                  _isReverseMode
                                      ? "- TAX (EXCL)"
                                      : "+ TAX (INCL)",
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: _isReverseMode
                                        ? scheme.onErrorContainer
                                        : scheme.onTertiaryContainer,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      Expanded(
                        flex: 6,
                        child: Container(
                          padding: const EdgeInsets.only(
                            left: 12,
                            right: 12,
                            bottom: 0,
                          ),
                          child: Row(
                            children: [
                              AnimatedContainer(
                                duration: const Duration(milliseconds: 300),
                                curve: Curves.easeInOutCubic,
                                width: _isExpanded ? 75.0 : 0.0,
                                clipBehavior: Clip.hardEdge,
                                decoration: const BoxDecoration(),
                                child: Column(
                                  children: [
                                    _gstBtn("0%", 0, userColor),
                                    _gstBtn("6%", 6, userColor),
                                    _gstBtn("9%", 9, userColor),
                                    _gstBtn("12%", 12, userColor),
                                    _gstBtn(
                                      "18%",
                                      18,
                                      userColor,
                                      isStandard: true,
                                    ),
                                    _gstBtn("28%", 28, userColor),
                                  ],
                                ),
                              ),
                              Expanded(
                                child: Column(
                                  children: [
                                    _row(["C", "÷", "x", "⌫"], scheme),
                                    _row(["7", "8", "9", "-"], scheme),
                                    _row(["4", "5", "6", "+"], scheme),
                                    _row(
                                      ["1", "2", "3", "="],
                                      scheme,
                                      isAction: true,
                                    ),
                                    _row(["%", "0", "00", "."], scheme),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 5. TAB 2: CURRENCY CONVERTER (API FALLBACK & KEYBOARD UX)
// ---------------------------------------------------------------------------
class CurrencyTab extends StatefulWidget {
  final Function(String) onSendToCalc;
  const CurrencyTab({super.key, required this.onSendToCalc});

  @override
  State<CurrencyTab> createState() => _CurrencyTabState();
}

class _CurrencyTabState extends State<CurrencyTab> {
  final TextEditingController _amountController = TextEditingController(
    text: "100",
  );
  String _fromCurrency = "USD";
  String _toCurrency = "INR";
  double _convertedAmount = 0.0;
  bool _isLoading = true;

  // Real fallback rates if API fails
  final Map<String, double> _rates = {
    "USD": 1.00,
    "EUR": 0.92,
    "GBP": 0.79,
    "INR": 83.50,
    "CNY": 7.23,
    "JPY": 151.50,
    "AUD": 1.52,
    "CAD": 1.35,
    "CHF": 0.90,
    "HKD": 7.82,
    "SGD": 1.34,
    "AED": 3.67,
    "SAR": 3.75,
    "ZAR": 18.80,
    "BRL": 5.05,
    "MXN": 16.50,
    "RUB": 92.50,
    "KRW": 1345.0,
    "SEK": 10.60,
    "NZD": 1.66,
  };

  @override
  void initState() {
    super.initState();
    _fetchLiveRates();
  }

  @override
  void dispose() {
    _amountController.dispose();
    super.dispose();
  }

  Future<void> _fetchLiveRates() async {
    try {
      final response = await http.get(
        Uri.parse('https://api.exchangerate-api.com/v4/latest/USD'),
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final Map<String, dynamic> apiRates = data['rates'];
        setState(() {
          _rates.forEach((key, value) {
            if (apiRates.containsKey(key)) {
              _rates[key] = (apiRates[key] as num).toDouble();
            }
          });
          _isLoading = false;
        });
      }
    } catch (e) {
      // UX FIX: Silently fail and use fallback _rates (no red error screens)
      setState(() => _isLoading = false);
    }
    _calculateConversion();
  }

  void _calculateConversion() {
    double amount = double.tryParse(_amountController.text) ?? 0.0;
    if (amount == 0) {
      setState(() => _convertedAmount = 0.0);
      return;
    }
    double amountInUsd = amount / _rates[_fromCurrency]!;
    setState(() => _convertedAmount = amountInUsd * _rates[_toCurrency]!);
  }

  void _swapCurrencies() {
    HapticFeedback.mediumImpact();
    setState(() {
      String temp = _fromCurrency;
      _fromCurrency = _toCurrency;
      _toCurrency = temp;
      _calculateConversion();
    });
  }

  Widget _buildCurrencyDropdown(String value, ValueChanged<String?> onChanged) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(12),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: value,
          icon: const Icon(Icons.keyboard_arrow_down),
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 18,
            color: Theme.of(context).colorScheme.onSurface,
          ),
          items: _rates.keys
              .map((String c) => DropdownMenuItem(value: c, child: Text(c)))
              .toList(),
          onChanged: onChanged,
        ),
      ),
    );
  }

  Widget _buildTimeZones() {
    final scheme = Theme.of(context).colorScheme;
    final zones = [
      {
        "city": "Mumbai",
        "flag": "🇮🇳",
        "h": 5,
        "m": 30,
      }, // Optimized for your vision
      {"city": "New York", "flag": "🇺🇸", "h": -4, "m": 0},
      {"city": "London", "flag": "🇬🇧", "h": 0, "m": 0},
      {"city": "Dubai", "flag": "🇦🇪", "h": 4, "m": 0},
      {"city": "Tokyo", "flag": "🇯🇵", "h": 9, "m": 0},
    ];

    DateTime utcNow = DateTime.now().toUtc();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          "Global Markets",
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: scheme.onSurface,
          ),
        ),
        const SizedBox(height: 12),
        ...zones.map((z) {
          DateTime localTime = utcNow.add(
            Duration(hours: z["h"] as int, minutes: z["m"] as int),
          );
          String ampm = localTime.hour >= 12 ? "PM" : "AM";
          int hour12 = localTime.hour % 12;
          hour12 = hour12 == 0 ? 12 : hour12;
          String minute = localTime.minute.toString().padLeft(2, '0');
          String timeString = "$hour12:$minute $ampm";
          // Basic 9-to-5 market logic
          bool isOpen = localTime.hour >= 9 && localTime.hour < 17;

          return Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHighest.withOpacity(0.3),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Text(
                      z["flag"] as String,
                      style: const TextStyle(fontSize: 24),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      z["city"] as String,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                  ],
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      timeString,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    Text(
                      isOpen ? "Market Open" : "Market Closed",
                      style: TextStyle(
                        fontSize: 12,
                        color: isOpen ? Colors.green : Colors.grey,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          );
        }),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        // UX FIX: Wrapped in scroll view so keyboard doesn't cause overflow errors
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    "Live Exchange",
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      color: scheme.onSurface,
                    ),
                  ),
                  if (_isLoading)
                    const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                "Real-time internet rates",
                style: TextStyle(color: scheme.onSurfaceVariant),
              ),
              const SizedBox(height: 20),
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHighest.withOpacity(0.4),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(
                    color: scheme.outlineVariant.withOpacity(0.3),
                  ),
                ),
                child: Column(
                  children: [
                    Row(
                      children: [
                        _buildCurrencyDropdown(_fromCurrency, (val) {
                          if (val != null) {
                            setState(() => _fromCurrency = val);
                            _calculateConversion();
                          }
                        }),
                        const SizedBox(width: 16),
                        Expanded(
                          child: TextField(
                            controller: _amountController,
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            textAlign: TextAlign.right,
                            style: const TextStyle(
                              fontSize: 32,
                              fontWeight: FontWeight.w500,
                            ),
                            decoration: const InputDecoration(
                              border: InputBorder.none,
                              isDense: true,
                            ),
                            onChanged: (value) => _calculateConversion(),
                          ),
                        ),
                      ],
                    ),
                    Stack(
                      alignment: Alignment.center,
                      children: [
                        Divider(
                          color: scheme.outlineVariant.withOpacity(0.5),
                          height: 40,
                        ),
                        GestureDetector(
                          onTap: _swapCurrencies,
                          child: CircleAvatar(
                            backgroundColor: scheme.primary,
                            foregroundColor: scheme.onPrimary,
                            radius: 20,
                            child: const Icon(Icons.swap_vert),
                          ),
                        ),
                      ],
                    ),
                    Row(
                      children: [
                        _buildCurrencyDropdown(_toCurrency, (val) {
                          if (val != null) {
                            setState(() => _toCurrency = val);
                            _calculateConversion();
                          }
                        }),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Text(
                            _convertedAmount.toStringAsFixed(2),
                            textAlign: TextAlign.right,
                            style: TextStyle(
                              fontSize: 32,
                              fontWeight: FontWeight.bold,
                              color: scheme.primary,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton.icon(
                  onPressed: () {
                    HapticFeedback.heavyImpact();
                    widget.onSendToCalc(_convertedAmount.toStringAsFixed(2));
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          'Copied ${_convertedAmount.toStringAsFixed(2)} $_toCurrency to Calculator!',
                        ),
                      ),
                    );
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: scheme.primary,
                    foregroundColor: scheme.onPrimary,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  icon: const Icon(Icons.check_circle),
                  label: const Text(
                    "Use in Calculator",
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
              const SizedBox(height: 30),
              _buildTimeZones(),
              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 6. TAB 3: PRICE BOOK (CSV COMMA BUG FIX & NATIVE FILES)
// ---------------------------------------------------------------------------
class PriceBookTab extends StatefulWidget {
  final Function(String) onSendToCalc;
  const PriceBookTab({super.key, required this.onSendToCalc});

  @override
  State<PriceBookTab> createState() => _PriceBookTabState();
}

class _PriceBookTabState extends State<PriceBookTab> {
  List<ProductItem> _products = [];
  List<ProductItem> _filteredProducts = [];
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadProducts();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadProducts() async {
    final prefs = await SharedPreferences.getInstance();
    final String? productsJson = prefs.getString('vyapar_products');
    if (productsJson != null) {
      final List<dynamic> decoded = jsonDecode(productsJson);
      setState(() {
        _products = decoded.map((x) => ProductItem.fromJson(x)).toList();
        _filteredProducts = List.from(_products);
      });
    } else {
      // Default stock for testing
      setState(() {
        _products = [
          ProductItem(name: "Clear Silicone Sealant (300ml)", price: 250.0),
          ProductItem(name: "Heavy Duty Caulking Gun", price: 450.0),
          ProductItem(name: "Masking Tape (2 inch)", price: 65.0),
        ];
        _filteredProducts = List.from(_products);
      });
      _saveProducts();
    }
  }

  Future<void> _saveProducts() async {
    final prefs = await SharedPreferences.getInstance();
    final String encoded = jsonEncode(
      _products.map((p) => p.toJson()).toList(),
    );
    await prefs.setString('vyapar_products', encoded);
  }

  void _filterSearch(String query) {
    setState(() {
      if (query.isEmpty) {
        _filteredProducts = List.from(_products);
      } else {
        _filteredProducts = _products
            .where((p) => p.name.toLowerCase().contains(query.toLowerCase()))
            .toList();
      }
    });
  }

  void _showAddProductDialog() {
    final nameController = TextEditingController();
    final priceController = TextEditingController();
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text("Add New Product"),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                decoration: const InputDecoration(
                  labelText: "Product Name",
                  prefixIcon: Icon(Icons.inventory),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: priceController,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  labelText: "Price",
                  prefixText: "₹ ",
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("Cancel"),
            ),
            ElevatedButton(
              onPressed: () {
                double? parsedPrice = double.tryParse(
                  priceController.text.trim(),
                );
                if (nameController.text.isNotEmpty && parsedPrice != null) {
                  setState(() {
                    _products.add(
                      ProductItem(
                        name: nameController.text.trim(),
                        price: parsedPrice,
                      ),
                    );
                    _filterSearch(_searchController.text);
                  });
                  _saveProducts();
                  Navigator.pop(context);
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Please enter a valid name and number.'),
                    ),
                  );
                }
              },
              child: const Text("Save"),
            ),
          ],
        );
      },
    );
  }

  // --- NATIVE FILE EXPORT (PRIVACY SAFE) ---
  void _exportCSV() async {
    String csvData = "Product Name,Price\n";
    for (var p in _products) {
      csvData += "${p.name},${p.price}\n";
    }

    try {
      final bytes = utf8.encode(csvData);
      final file = XFile.fromData(
        Uint8List.fromList(bytes),
        name: 'vyapar_pricebook.csv',
        mimeType: 'text/csv',
      );

      // Hands file to OS share sheet (automatically downloads on web)
      await Share.shareXFiles([file], text: 'Vyapar Price Book Backup');
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Error exporting file.')));
    }
  }

  // --- NATIVE FILE IMPORT (PRIVACY SAFE) ---
  void _importCSV() async {
    try {
      // Opens system file browser (no storage permission popups)
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['csv'],
        withData: true, // Needed for web
      );

      if (result != null && result.files.single.bytes != null) {
        String contents = utf8.decode(result.files.single.bytes!);
        int addedCount = 0;
        List<String> lines = contents.split('\n');

        setState(() {
          for (int i = 0; i < lines.length; i++) {
            if (lines[i].trim().isEmpty) continue;
            // Skip header
            if (i == 0 && lines[i].toLowerCase().contains("name")) continue;

            // BUG FIX: Smart regex avoids breaking if product names contain commas (e.g., from Excel)
            List<String> parts = lines[i].split(
              RegExp(r',(?=(?:[^\"]*\"[^\"]*\")*[^\"]*$)'),
            );

            if (parts.length >= 2) {
              String name = parts[0].replaceAll('"', '').trim();
              String priceStr = parts[1].replaceAll(RegExp(r'[^0-9.]'), '');
              double? price = double.tryParse(priceStr);

              if (name.isNotEmpty && price != null) {
                _products.add(ProductItem(name: name, price: price));
                addedCount++;
              }
            }
          }
          _filterSearch(_searchController.text);
        });
        _saveProducts();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Successfully imported $addedCount products!'),
          ),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Error reading file.')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SafeArea(
      child: Stack(
        children: [
          Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      "Price Book",
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                        color: scheme.onSurface,
                      ),
                    ),
                    PopupMenuButton<String>(
                      icon: const Icon(Icons.more_vert),
                      onSelected: (value) {
                        if (value == 'Import') _importCSV();
                        if (value == 'Export') _exportCSV();
                      },
                      itemBuilder: (BuildContext context) => [
                        const PopupMenuItem(
                          value: 'Import',
                          child: Row(
                            children: [
                              Icon(Icons.file_download),
                              SizedBox(width: 8),
                              Text('Import CSV File'),
                            ],
                          ),
                        ),
                        const PopupMenuItem(
                          value: 'Export',
                          child: Row(
                            children: [
                              Icon(Icons.file_upload),
                              SizedBox(width: 8),
                              Text('Export CSV File'),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0),
                child: TextField(
                  controller: _searchController,
                  onChanged: _filterSearch,
                  decoration: InputDecoration(
                    hintText: "Search products...",
                    prefixIcon: const Icon(Icons.search),
                    filled: true,
                    fillColor: scheme.surfaceContainerHighest.withOpacity(0.3),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Expanded(
                child: ListView.builder(
                  // Bottom padding ensures FAB doesn't block last item
                  padding: const EdgeInsets.only(
                    left: 16,
                    right: 16,
                    top: 16,
                    bottom: 80,
                  ),
                  itemCount: _filteredProducts.length,
                  itemBuilder: (context, index) {
                    final product = _filteredProducts[index];
                    return Card(
                      margin: const EdgeInsets.only(bottom: 12),
                      elevation: 0,
                      color: scheme.surfaceContainerHighest.withOpacity(0.3),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: ListTile(
                        title: Text(
                          product.name,
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        subtitle: Text(
                          "₹ ${product.price.toStringAsFixed(2)}",
                          style: TextStyle(
                            color: scheme.primary,
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                        trailing: IconButton(
                          icon: const Icon(Icons.add_shopping_cart),
                          color: scheme.primary,
                          onPressed: () {
                            HapticFeedback.lightImpact();
                            widget.onSendToCalc(
                              product.price.toStringAsFixed(2),
                            );
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  'Added ${product.name} to Calculator!',
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
          Positioned(
            bottom: 24,
            right: 24,
            child: FloatingActionButton(
              onPressed: _showAddProductDialog,
              backgroundColor: scheme.primary,
              foregroundColor: scheme.onPrimary,
              elevation: 4,
              child: const Icon(Icons.add),
            ),
          ),
        ],
      ),
    );
  }
}
