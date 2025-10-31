import 'package:flutter/material.dart';
import '../services/database_helper.dart';
import 'manage_cc_screen.dart';

class EditCcScreen extends StatelessWidget {
  final Map<String, dynamic> cc;

  const EditCcScreen({Key? key, required this.cc}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Edit CC: ${cc['name']}')),
      body: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          children: [
            Text('Editing CC: ${cc['email'] ?? 'Unknown'}'),
            const SizedBox(height: 16),
            Expanded(
              child: FutureBuilder<List<Map<String, dynamic>>>(
                future: DatabaseHelper.instance.getClassCombinations(),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (snapshot.hasError) {
                    return Center(child: Text('Error: ${snapshot.error}'));
                  }
                  final classes = snapshot.data ?? [];
                  if (classes.isEmpty) {
                    return const Center(child: Text('No classes available'));
                  }
                  return ListView.builder(
                    itemCount: classes.length,
                    itemBuilder: (context, idx) {
                      final classData = classes[idx];
                      final className = '${classData['semester']}${classData['department']}-${classData['division']}';
                      final isAssigned = (cc['classes'] as List<dynamic>?)?.contains(className) ?? false;
                      return Card(
                        child: ListTile(
                          title: Text(className),
                          trailing: Icon(
                            isAssigned ? Icons.check_box : Icons.check_box_outline_blank,
                            color: isAssigned ? Colors.green : null,
                          ),
                          onTap: () async {
                            // Toggle class assignment
                            final newAssignedClasses = List<String>.from(cc['classes'] ?? []);
                            if (isAssigned) {
                              newAssignedClasses.remove(className);
                            } else {
                              newAssignedClasses.add(className);
                            }
                            await DatabaseHelper.instance.updateUserClasses(cc['email'], newAssignedClasses);
                            // Refresh the CC data
                            Navigator.of(context).pop();
                            Navigator.of(context).push(MaterialPageRoute(builder: (context) => ManageCcScreen()));
                          },
                        ),
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
}
