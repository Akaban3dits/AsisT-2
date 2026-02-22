import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:excel/excel.dart';

import '../../generations/models/generation.dart';
import '../data/student_repository.dart';
import '../models/student.dart';
import 'student_report_page.dart';
import '../../attendance/presentation/attendance_page.dart';
import '../../attendance/data/attendance_repository.dart';

class StudentsPage extends StatefulWidget {
  final Generation generation;

  const StudentsPage({super.key, required this.generation});

  @override
  State<StudentsPage> createState() => _StudentsPageState();
}

class _StudentsPageState extends State<StudentsPage>
    with SingleTickerProviderStateMixin {
  final StudentRepository _repository = StudentRepository();
  final TextEditingController _searchController = TextEditingController();

  List<Student> _students = [];
  List<Student> _filteredStudents = [];
  bool _isLoading = true;

  late AnimationController _animController;
  late Animation<double> _fadeAnim;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      duration: const Duration(milliseconds: 400),
      vsync: this,
    );

    _fadeAnim = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _animController, curve: Curves.easeOut));

    _loadStudents();
  }

  Future<void> _loadStudents() async {
    setState(() => _isLoading = true);

    try {
      final data = await _repository.getByGeneration(widget.generation.id!);

      if (!mounted) return;

      setState(() {
        _students = data;
        _filteredStudents = data;
        _isLoading = false;
      });

      _animController.forward(from: 0);
    } catch (e) {
      debugPrint("❌ Error cargando estudiantes: $e");
      if (mounted) {
        setState(() => _isLoading = false);
        _showSnackBar("Error al cargar estudiantes: $e", isError: true);
      }
    }
  }

  void _filterStudents(String query) {
    setState(() {
      if (query.isEmpty) {
        _filteredStudents = _students;
      } else {
        _filteredStudents = _students
            .where((s) => s.name.toLowerCase().contains(query.toLowerCase()))
            .toList();
      }
    });
  }

  Future<void> _importFromExcel() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['xlsx'],
      );

      if (result == null) return;

      final file = File(result.files.single.path!);
      final bytes = file.readAsBytesSync();
      final excel = Excel.decodeBytes(bytes);

      List<Student> studentsToInsert = [];

      for (var table in excel.tables.keys) {
        final sheet = excel.tables[table];
        if (sheet == null) continue;

        for (var row in sheet.rows) {
          if (row.isEmpty) continue;

          final cellValue = row[0]?.value;

          if (cellValue != null && cellValue.toString().trim().isNotEmpty) {
            studentsToInsert.add(
              Student(
                name: cellValue.toString().trim(),
                generationId: widget.generation.id!,
              ),
            );
          }
        }
      }

      if (studentsToInsert.isEmpty) {
        _showSnackBar("No se encontraron estudiantes válidos en el archivo", isError: true);
        return;
      }

      await _repository.bulkInsert(studentsToInsert);
      await _loadStudents();

      HapticFeedback.mediumImpact();
      _showSnackBar(
        "${studentsToInsert.length} estudiantes importados exitosamente",
        isError: false,
      );
    } catch (e) {
      _showSnackBar("Error al importar archivo: $e", isError: true);
    }
  }

  Future<void> _exportToExcel() async {
  try {
    if (_students.isEmpty) {
      _showSnackBar("No hay estudiantes para exportar", isError: true);
      return;
    }

    // Crear el archivo Excel
    var excel = Excel.createExcel();
    excel.delete('Sheet1'); // Eliminar hoja por defecto

    // Obtener todos los registros de asistencia
    final attendanceRepo = AttendanceRepository();
    Map<String, Map<int, Map<String, String>>> monthlyData = {};

    // Organizar datos por mes
    for (var student in _students) {
      if (student.id == null) continue;
      
      final records = await attendanceRepo.getStudentReport(student.id!);
      
      for (var record in records) {
        final date = DateTime.parse(record['date'] as String);
        final monthKey = '${_getMonthAbbr(date.month)}${date.year.toString().substring(2)}';
        final dateKey = record['date'] as String;
        
        if (!monthlyData.containsKey(monthKey)) {
          monthlyData[monthKey] = {};
        }
        if (!monthlyData[monthKey]!.containsKey(student.id)) {
          monthlyData[monthKey]![student.id!] = {};
        }
        
        monthlyData[monthKey]![student.id!]![dateKey] = record['status'] as String;
      }
    }

    // Crear una hoja por cada mes que tenga datos
    final sortedMonths = monthlyData.keys.toList()..sort((a, b) {
      final dateA = _parseMonthKey(a);
      final dateB = _parseMonthKey(b);
      return dateA.compareTo(dateB);
    });

    for (var monthKey in sortedMonths) {
      var sheet = excel[monthKey];
      
      // Obtener todas las fechas únicas del mes y ordenarlas
      Set<String> allDates = {};
      for (var studentData in monthlyData[monthKey]!.values) {
        allDates.addAll(studentData.keys);
      }
      final sortedDates = allDates.toList()..sort();

      // ENCABEZADO - Fila 1: "Fecha"
      sheet.cell(CellIndex.indexByString('A1'))
        ..value = TextCellValue('Fecha')
        ..cellStyle = CellStyle(
          bold: true,
          fontSize: 12,
          horizontalAlign: HorizontalAlign.Center,
          verticalAlign: VerticalAlign.Center,
        );

      // ENCABEZADO - Fila 1: Fechas formateadas
      for (int i = 0; i < sortedDates.length; i++) {
        final date = DateTime.parse(sortedDates[i]);
        final formattedDate = '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year.toString().substring(2)}';
        
        sheet.cell(CellIndex.indexByColumnRow(columnIndex: i + 1, rowIndex: 0))
          ..value = TextCellValue(formattedDate)
          ..cellStyle = CellStyle(
            bold: true,
            fontSize: 11,
            horizontalAlign: HorizontalAlign.Center,
            verticalAlign: VerticalAlign.Center,
          );
      }

      // DATOS - Filas de estudiantes
      for (int studentIdx = 0; studentIdx < _students.length; studentIdx++) {
        final student = _students[studentIdx];
        final rowIndex = studentIdx + 1;
        
        // Nombre del estudiante
        sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: rowIndex))
          ..value = TextCellValue(student.name)
          ..cellStyle = CellStyle(
            bold: true,
            fontSize: 11,
          );

        // Estados de asistencia
        final studentData = monthlyData[monthKey]![student.id] ?? {};
        
        for (int dateIdx = 0; dateIdx < sortedDates.length; dateIdx++) {
          final date = sortedDates[dateIdx];
          final status = studentData[date];
          final colIndex = dateIdx + 1;
          
          final cell = sheet.cell(CellIndex.indexByColumnRow(
            columnIndex: colIndex,
            rowIndex: rowIndex,
          ));

          if (status != null) {
            String displayValue = '';
            String bgColor = 'FFFFFFFF';
            
            switch (status) {
              case 'present':
                displayValue = 'P';
                bgColor = 'FF10B981'; // Verde
                break;
              case 'late':
                displayValue = 'R';
                bgColor = 'FFF59E0B'; // Amarillo
                break;
              case 'absent':
                displayValue = 'F';
                bgColor = 'FFEF4444'; // Rojo
                break;
              case 'justified':
                displayValue = 'J';
                bgColor = 'FF3B82F6'; // Azul
                break;
            }
            
            cell
              ..value = TextCellValue(displayValue)
              ..cellStyle = CellStyle(
                bold: true,
                fontSize: 11,
                fontColorHex: ExcelColor.white,
                backgroundColorHex: ExcelColor.fromHexString(bgColor),
                horizontalAlign: HorizontalAlign.Center,
                verticalAlign: VerticalAlign.Center,
              );
          }
        }
      }

      // SIMBOLOGÍA - Después de todos los estudiantes
      final legendRow = _students.length + 3;
      
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: legendRow))
        ..value = TextCellValue('SIMBOLOGÍA:')
        ..cellStyle = CellStyle(
          bold: true,
          fontSize: 12,
        );

      // P - Presente
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: legendRow + 1))
        ..value = TextCellValue('P')
        ..cellStyle = CellStyle(
          bold: true,
          fontSize: 11,
          fontColorHex: ExcelColor.white,
          backgroundColorHex: ExcelColor.fromHexString('FF10B981'),
          horizontalAlign: HorizontalAlign.Center,
        );
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: legendRow + 1))
        ..value = TextCellValue('Presente')
        ..cellStyle = CellStyle(fontSize: 11);

      // R - Retardo
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: legendRow + 2))
        ..value = TextCellValue('R')
        ..cellStyle = CellStyle(
          bold: true,
          fontSize: 11,
          fontColorHex: ExcelColor.white,
          backgroundColorHex: ExcelColor.fromHexString('FFF59E0B'),
          horizontalAlign: HorizontalAlign.Center,
        );
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: legendRow + 2))
        ..value = TextCellValue('Retardo')
        ..cellStyle = CellStyle(fontSize: 11);

      // F - Falta
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: legendRow + 3))
        ..value = TextCellValue('F')
        ..cellStyle = CellStyle(
          bold: true,
          fontSize: 11,
          fontColorHex: ExcelColor.white,
          backgroundColorHex: ExcelColor.fromHexString('FFEF4444'),
          horizontalAlign: HorizontalAlign.Center,
        );
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: legendRow + 3))
        ..value = TextCellValue('Falta')
        ..cellStyle = CellStyle(fontSize: 11);

      // J - Justificado
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: legendRow + 4))
        ..value = TextCellValue('J')
        ..cellStyle = CellStyle(
          bold: true,
          fontSize: 11,
          fontColorHex: ExcelColor.white,
          backgroundColorHex: ExcelColor.fromHexString('FF3B82F6'),
          horizontalAlign: HorizontalAlign.Center,
        );
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: legendRow + 4))
        ..value = TextCellValue('Justificado')
        ..cellStyle = CellStyle(fontSize: 11);

      // Ajustar ancho de columnas
      sheet.setColumnWidth(0, 25); // Nombres
      for (int i = 1; i <= sortedDates.length; i++) {
        sheet.setColumnWidth(i, 12); // Fechas
      }
    }

    // Guardar archivo - Generate bytes first
    final fileBytes = excel.encode();
    if (fileBytes == null) {
      _showSnackBar("Error al generar archivo Excel", isError: true);
      return;
    }

    // **FIXED: Provide bytes to saveFile**
    final fileName = 'Asistencia_${widget.generation.name}_${DateTime.now().toString().substring(0, 10)}.xlsx';
    
    final String? outputFile = await FilePicker.platform.saveFile(
      dialogTitle: 'Guardar archivo Excel',
      fileName: fileName,
      type: FileType.custom,
      allowedExtensions: ['xlsx'],
      bytes: Uint8List.fromList(fileBytes),  // convert List<int> to Uint8List
    );

    if (outputFile == null) {
      // User canceled the picker
      return;
    }

    HapticFeedback.mediumImpact();
    _showSnackBar("Excel exportado exitosamente", isError: false);
  } catch (e) {
    debugPrint("Error exportando: $e");
    _showSnackBar("Error al exportar archivo: $e", isError: true);
  }
}

  String _getMonthAbbr(int month) {
    const months = [
      'Ene',
      'Feb',
      'Mar',
      'Abr',
      'May',
      'Jun',
      'Jul',
      'Ago',
      'Sep',
      'Oct',
      'Nov',
      'Dic',
    ];
    return months[month - 1];
  }

  DateTime _parseMonthKey(String key) {
    // Ejemplo: "Ene26" -> enero 2026
    final monthAbbr = key.substring(0, 3);
    final year = int.parse('20${key.substring(3)}');

    const months = [
      'Ene',
      'Feb',
      'Mar',
      'Abr',
      'May',
      'Jun',
      'Jul',
      'Ago',
      'Sep',
      'Oct',
      'Nov',
      'Dic',
    ];
    final month = months.indexOf(monthAbbr) + 1;

    return DateTime(year, month);
  }

  void _showSnackBar(String message, {required bool isError}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError
            ? const Color(0xFFE63946)
            : const Color(0xFF10B981),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(16),
      ),
    );
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
    _searchController.dispose();
    _animController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            _buildStatsBar(),
            if (_students.isNotEmpty) _buildSearchBar(),
            Expanded(
              child: _isLoading
                  ? const Center(
                      child: CircularProgressIndicator(
                        color: Color(0xFF6366F1),
                        strokeWidth: 3,
                      ),
                    )
                  : _students.isEmpty
                  ? _buildEmptyState()
                  : _buildStudentsList(),
            ),
          ],
        ),
      ),
      floatingActionButton: _buildFAB(),
    );
  }

  Widget _buildHeader() {
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
                const Text(
                  "Estudiantes",
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF1E293B),
                    letterSpacing: -0.5,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  widget.generation.name,
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
            onTap: _exportToExcel,
            child: Container(
              width: 40,
              height: 40,
              margin: const EdgeInsets.only(right: 8),
              decoration: BoxDecoration(
                color: const Color(0xFFF1F5F9),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(
                Icons.download_rounded,
                color: Color(0xFF10B981),
                size: 20,
              ),
            ),
          ),
          GestureDetector(
            onTap: _importFromExcel,
            child: Container(
              width: 40,
              height: 40,
              margin: const EdgeInsets.only(right: 8),
              decoration: BoxDecoration(
                color: const Color(0xFFF1F5F9),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(
                Icons.upload_file_rounded,
                color: Color(0xFF6366F1),
                size: 20,
              ),
            ),
          ),
          GestureDetector(
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => AttendancePage(generation: widget.generation),
                ),
              );
            },
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
                Icons.checklist_rounded,
                color: Colors.white,
                size: 20,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatsBar() {
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
      child: Row(
        children: [
          Expanded(
            child: Column(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF6366F1), Color(0xFF8B5CF6)],
                    ),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Center(
                    child: Text(
                      _students.length.toString(),
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.people_rounded,
                      size: 14,
                      color: const Color(0xFF6366F1).withOpacity(0.7),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      "Total Estudiantes",
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
          ),
        ],
      ),
    );
  }

  Widget _buildSearchBar() {
    return Container(
      margin: const EdgeInsets.fromLTRB(20, 0, 20, 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 20,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: TextField(
        controller: _searchController,
        onChanged: _filterStudents,
        decoration: InputDecoration(
          hintText: "Buscar estudiantes...",
          hintStyle: TextStyle(color: Colors.grey[400], fontSize: 15),
          prefixIcon: Icon(
            Icons.search_rounded,
            color: Colors.grey[400],
            size: 22,
          ),
          suffixIcon: _searchController.text.isNotEmpty
              ? IconButton(
                  icon: Icon(
                    Icons.clear_rounded,
                    color: Colors.grey[400],
                    size: 20,
                  ),
                  onPressed: () {
                    _searchController.clear();
                    _filterStudents('');
                  },
                )
              : null,
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 20,
            vertical: 16,
          ),
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
              Icons.school_rounded,
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
            "Agrega estudiantes para comenzar",
            style: TextStyle(fontSize: 16, color: Colors.grey[600]),
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: _showAddDialog,
            icon: const Icon(Icons.add_rounded, size: 20),
            label: const Text("Agregar Estudiante"),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF6366F1),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              elevation: 0,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStudentsList() {
    return FadeTransition(
      opacity: _fadeAnim,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 100),
        itemCount: _filteredStudents.length,
        itemBuilder: (context, index) {
          final student = _filteredStudents[index];
          return _buildStudentCard(student, index);
        },
      ),
    );
  }

  Widget _buildStudentCard(Student student, int index) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
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
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: () {
            HapticFeedback.selectionClick();
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => StudentReportPage(student: student),
              ),
            );
          },
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                // Avatar
                Container(
                  width: 56,
                  height: 56,
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
                        color: _getStudentColor(index).withOpacity(0.3),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Center(
                    child: Text(
                      _getInitials(student.name),
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                // Name
                Expanded(
                  child: Text(
                    student.name,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF1E293B),
                      letterSpacing: -0.3,
                    ),
                  ),
                ),
                // Delete button
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: const Color(0xFFEF4444).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: IconButton(
                    icon: const Icon(
                      Icons.delete_rounded,
                      size: 18,
                      color: Color(0xFFEF4444),
                    ),
                    padding: EdgeInsets.zero,
                    onPressed: () => _showDeleteDialog(student),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFAB() {
    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF6366F1), Color(0xFF8B5CF6)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF6366F1).withOpacity(0.4),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: FloatingActionButton(
        onPressed: _showAddDialog,
        backgroundColor: Colors.transparent,
        elevation: 0,
        child: const Icon(Icons.add_rounded, size: 28),
      ),
    );
  }

  void _showAddDialog() {
    final TextEditingController controller = TextEditingController();

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          title: const Text(
            "Agregar Estudiante",
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: Color(0xFF1E293B),
            ),
          ),
          content: SingleChildScrollView(
            child: TextField(
              controller: controller,
              autofocus: true,
              decoration: InputDecoration(
                hintText: "Nombre del estudiante",
                hintStyle: TextStyle(color: Colors.grey[400]),
                filled: true,
                fillColor: const Color(0xFFF8FAFC),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(
                    color: Color(0xFF6366F1),
                    width: 2,
                  ),
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              style: TextButton.styleFrom(
                foregroundColor: Colors.grey[600],
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 12,
                ),
              ),
              child: const Text(
                "Cancelar",
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
              ),
            ),
            ElevatedButton(
              onPressed: () async {
                if (controller.text.trim().isNotEmpty) {
                  await _repository.insert(
                    Student(
                      name: controller.text.trim(),
                      generationId: widget.generation.id!,
                    ),
                  );
                  Navigator.pop(context);
                  HapticFeedback.mediumImpact();
                  _loadStudents();
                  _showSnackBar("Estudiante agregado exitosamente", isError: false);
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF6366F1),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 12,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                elevation: 0,
              ),
              child: const Text(
                "Guardar",
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        );
      },
    );
  }

  void _showDeleteDialog(Student student) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          title: const Row(
            children: [
              Icon(Icons.warning_rounded, color: Color(0xFFEF4444), size: 28),
              SizedBox(width: 12),
              Expanded(
                child: Text(
                  "Eliminar Estudiante",
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF1E293B),
                  ),
                ),
              ),
            ],
          ),
          content: SingleChildScrollView(
            child: Text(
              "¿Estás seguro de que quieres eliminar a ${student.name}? Esta acción no se puede deshacer.",
              style: TextStyle(
                fontSize: 15,
                color: Colors.grey[700],
                height: 1.5,
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              style: TextButton.styleFrom(
                foregroundColor: Colors.grey[600],
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 12,
                ),
              ),
              child: const Text(
                "Cancelar",
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
              ),
            ),
            ElevatedButton(
              onPressed: () async {
                await _repository.delete(student.id!);
                Navigator.pop(context);
                HapticFeedback.mediumImpact();
                _loadStudents();
                _showSnackBar("Estudiante eliminado", isError: false);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFEF4444),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 12,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                elevation: 0,
              ),
              child: const Text(
                "Eliminar",
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        );
      },
    );
  }
}