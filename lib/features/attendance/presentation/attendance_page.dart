import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../generations/models/generation.dart';
import '../../students/data/student_repository.dart';
import '../../students/models/student.dart';
import '../data/attendance_repository.dart';

class AttendancePage extends StatefulWidget {
  final Generation generation;

  const AttendancePage({super.key, required this.generation});

  @override
  State<AttendancePage> createState() => _AttendancePageState();
}

class _AttendancePageState extends State<AttendancePage>
    with SingleTickerProviderStateMixin {
  final StudentRepository _studentRepository = StudentRepository();
  final AttendanceRepository _attendanceRepository = AttendanceRepository();
  final PageController _pageController = PageController();
  final ValueNotifier<Map<int, String?>> _statusMap = ValueNotifier({});

  List<Student> _students = [];
  bool _isLoading = true;
  int? _sessionId;
  int _currentIndex = 0;
  DateTime _selectedDate = DateTime.now();

  late AnimationController _animController;
  late Animation<double> _scaleAnim;
  late Animation<double> _fadeAnim;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      duration: const Duration(milliseconds: 400),
      vsync: this,
    );

    _scaleAnim = Tween<double>(begin: 0.9, end: 1.0).animate(
      CurvedAnimation(parent: _animController, curve: Curves.easeOutBack),
    );

    _fadeAnim = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animController, curve: Curves.easeOut),
    );

    _initAttendance();
  }

  Future<void> _initAttendance() async {
    setState(() => _isLoading = true);

    try {
      final generationId = widget.generation.id!;
      final sessionId = await _attendanceRepository.createOrGetSessionByDate(
        generationId,
        _selectedDate,
      );

      final students = await _studentRepository.getByGeneration(generationId);
      final existing = await _attendanceRepository.getSessionStatuses(sessionId);

      _statusMap.value = {
        for (var s in students.where((s) => s.id != null)) s.id!: existing[s.id]
      };

      if (!mounted) return;

      setState(() {
        _students = students.where((s) => s.id != null).toList();
        _sessionId = sessionId;
        _isLoading = false;
        _currentIndex = 0;
      });

      _animController.forward(from: 0);
    } catch (e) {
      debugPrint("❌ Error: $e");
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Error al cargar asistencia: $e"),
            backgroundColor: const Color(0xFFE63946),
          ),
        );
      }
    }
  }

  Future<void> _setStatus(int studentId, String status) async {
    HapticFeedback.mediumImpact();

    final map = Map<int, String?>.from(_statusMap.value);
    map[studentId] = status;
    _statusMap.value = map;

    _attendanceRepository.saveRecord(_sessionId!, studentId, status).catchError((e) {
      debugPrint("Error al guardar: $e");
    });

    await Future.delayed(const Duration(milliseconds: 150));

    if (_currentIndex < _students.length - 1) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeInOutCubic,
      );
    }
  }

  Future<void> _selectDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: Color(0xFF6366F1),
              onPrimary: Colors.white,
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked != null && picked != _selectedDate) {
      setState(() => _selectedDate = picked);
      _initAttendance();
    }
  }

  String _getInitials(String name) {
    if (name.isEmpty) return "?";
    final parts = name.trim().split(" ").where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return "?";
    if (parts.length == 1) return parts.first[0].toUpperCase();
    return (parts.first[0] + parts.last[0]).toUpperCase();
  }

  Color _getStudentColor(int index) {
    final colors = [
      const Color(0xFF6366F1), // Indigo
      const Color(0xFF8B5CF6), // Purple
      const Color(0xFFEC4899), // Pink
      const Color(0xFF10B981), // Green
      const Color(0xFFF59E0B), // Amber
      const Color(0xFF3B82F6), // Blue
    ];
    return colors[index % colors.length];
  }

  @override
  void dispose() {
    _pageController.dispose();
    _animController.dispose();
    _statusMap.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(
                color: Color(0xFF6366F1),
                strokeWidth: 3,
              ),
            )
          : _students.isEmpty
              ? _buildEmptyState()
              : SafeArea(
                  child: Column(
                    children: [
                      _buildHeader(),
                      _buildStatsBar(),
                      _buildProgressIndicator(),
                      Expanded(
                        child: PageView.builder(
                          controller: _pageController,
                          itemCount: _students.length,
                          physics: const BouncingScrollPhysics(),
                          onPageChanged: (i) {
                            setState(() => _currentIndex = i);
                            HapticFeedback.selectionClick();
                            _animController.forward(from: 0);
                          },
                          itemBuilder: (_, index) {
                            final student = _students[index];
                            return ValueListenableBuilder<Map<int, String?>>(
                              valueListenable: _statusMap,
                              builder: (_, map, __) {
                                return _buildStudentCard(
                                  student,
                                  map[student.id],
                                  index,
                                );
                              },
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 140,
            height: 140,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  const Color(0xFF6366F1).withOpacity(0.1),
                  const Color(0xFF8B5CF6).withOpacity(0.1),
                ],
              ),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.people_outline_rounded,
              size: 70,
              color: Color(0xFF6366F1),
            ),
          ),
          const SizedBox(height: 32),
          const Text(
            "Sin estudiantes aún",
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: Color(0xFF1E293B),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            "Agrega estudiantes para comenzar a registrar asistencia",
            style: TextStyle(
              fontSize: 16,
              color: Colors.grey[600],
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    final months = [
      'Ene', 'Feb', 'Mar', 'Abr', 'May', 'Jun',
      'Jul', 'Ago', 'Sep', 'Oct', 'Nov', 'Dic'
    ];
    final dateStr = "${_selectedDate.day} ${months[_selectedDate.month - 1]}, ${_selectedDate.year}";

    return Container(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 16),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => Navigator.pop(context),
            child: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: const Color(0xFFF1F5F9),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(
                Icons.arrow_back_rounded,
                color: Color(0xFF1E293B),
                size: 20,
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.generation.name,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF1E293B),
                    letterSpacing: -0.5,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  dateStr,
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey[600],
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          GestureDetector(
            onTap: _selectDate,
            child: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF6366F1), Color(0xFF8B5CF6)],
                ),
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF6366F1).withOpacity(0.3),
                    blurRadius: 8,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: const Icon(
                Icons.calendar_today_rounded,
                color: Colors.white,
                size: 18,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatsBar() {
    return ValueListenableBuilder<Map<int, String?>>(
      valueListenable: _statusMap,
      builder: (_, map, __) {
        int present = 0, late = 0, absent = 0, justified = 0;
        for (var status in map.values) {
          if (status == 'present') present++;
          if (status == 'late') late++;
          if (status == 'absent') absent++;
          if (status == 'justified') justified++;
        }

        return Container(
          margin: const EdgeInsets.all(20),
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.04),
                blurRadius: 20,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            children: [
              Row(
                children: [
                  _buildStatItem(
                    present,
                    "Presente",
                    const Color(0xFF10B981),
                    Icons.check_circle_rounded,
                  ),
                  _buildDivider(),
                  _buildStatItem(
                    late,
                    "Retardo",
                    const Color(0xFFF59E0B),
                    Icons.schedule_rounded,
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  _buildStatItem(
                    absent,
                    "Falta",
                    const Color(0xFFEF4444),
                    Icons.cancel_rounded,
                  ),
                  _buildDivider(),
                  _buildStatItem(
                    justified,
                    "Justificado",
                    const Color(0xFF3B82F6),
                    Icons.verified_rounded,
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildStatItem(int value, String label, Color color, IconData icon) {
    return Expanded(
      child: Column(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Center(
              child: Text(
                value.toString(),
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 14, color: color.withOpacity(0.7)),
              const SizedBox(width: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey[700],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDivider() {
    return Container(
      width: 1,
      height: 40,
      margin: const EdgeInsets.symmetric(horizontal: 8),
      color: Colors.grey[200],
    );
  }

  Widget _buildProgressIndicator() {
    final progress = _students.isEmpty ? 0.0 : (_currentIndex + 1) / _students.length;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                "Progreso",
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey[700],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF6366F1), Color(0xFF8B5CF6)],
                  ),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  "${_currentIndex + 1}/${_students.length}",
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 8,
              backgroundColor: Colors.grey[200],
              valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF6366F1)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStudentCard(Student student, String? status, int index) {
    return FadeTransition(
      opacity: _fadeAnim,
      child: ScaleTransition(
        scale: _scaleAnim,
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Avatar y nombre
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(32),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.08),
                      blurRadius: 30,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    // Avatar con gradiente
                    Container(
                      width: 90,
                      height: 90,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            _getStudentColor(index),
                            _getStudentColor(index).withOpacity(0.7),
                          ],
                        ),
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: _getStudentColor(index).withOpacity(0.4),
                            blurRadius: 20,
                            offset: const Offset(0, 10),
                          ),
                        ],
                      ),
                      child: Center(
                        child: Text(
                          _getInitials(student.name),
                          style: const TextStyle(
                            fontSize: 32,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                            letterSpacing: 1,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    // Nombre
                    Text(
                      student.name,
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF1E293B),
                        letterSpacing: -0.5,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    if (status != null) ...[
                      const SizedBox(height: 8),
                      _buildStatusBadge(status),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 20),
              // Botones de acción
              _buildActionButtons(student.id!, status),
              const SizedBox(height: 40), // Espacio extra al final
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatusBadge(String status) {
    final configs = {
      'present': {
        'label': 'Presente',
        'color': const Color(0xFF10B981),
        'icon': Icons.check_circle_rounded,
      },
      'late': {
        'label': 'Retardo',
        'color': const Color(0xFFF59E0B),
        'icon': Icons.schedule_rounded,
      },
      'absent': {
        'label': 'Falta',
        'color': const Color(0xFFEF4444),
        'icon': Icons.cancel_rounded,
      },
      'justified': {
        'label': 'Justificado',
        'color': const Color(0xFF3B82F6),
        'icon': Icons.verified_rounded,
      },
    };

    final config = configs[status]!;
    final color = config['color'] as Color;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(config['icon'] as IconData, size: 16, color: color),
          const SizedBox(width: 6),
          Text(
            "Marcado ${config['label']}",
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButtons(int studentId, String? status) {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _buildButton(
                studentId: studentId,
                value: 'present',
                currentStatus: status,
                label: "Presente",
                icon: Icons.check_circle_rounded,
                color: const Color(0xFF10B981),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildButton(
                studentId: studentId,
                value: 'late',
                currentStatus: status,
                label: "Retardo",
                icon: Icons.schedule_rounded,
                color: const Color(0xFFF59E0B),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: _buildButton(
                studentId: studentId,
                value: 'absent',
                currentStatus: status,
                label: "Falta",
                icon: Icons.cancel_rounded,
                color: const Color(0xFFEF4444),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildButton(
                studentId: studentId,
                value: 'justified',
                currentStatus: status,
                label: "Justificado",
                icon: Icons.verified_rounded,
                color: const Color(0xFF3B82F6),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildButton({
    required int studentId,
    required String value,
    required String? currentStatus,
    required String label,
    required IconData icon,
    required Color color,
  }) {
    final isSelected = currentStatus == value;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      height: 56,
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: isSelected ? color : Colors.white,
          foregroundColor: isSelected ? Colors.white : color,
          elevation: isSelected ? 8 : 0,
          shadowColor: isSelected ? color.withOpacity(0.4) : Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(
              color: isSelected ? Colors.transparent : color.withOpacity(0.2),
              width: 2,
            ),
          ),
          padding: const EdgeInsets.symmetric(vertical: 12),
        ),
        onPressed: () => _setStatus(studentId, value),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 20),
            const SizedBox(width: 8),
            Text(
              label,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}