import 'package:flutter/material.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const AtlasNotesApp());
}

class AtlasNotesApp extends StatelessWidget {
  const AtlasNotesApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Atlas Notes',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: const Color(0xFF4F46E5),
        brightness: Brightness.light,
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: const Color(0xFF818CF8),
        brightness: Brightness.dark,
      ),
      home: const AtlasShell(),
    );
  }
}

class AtlasShell extends StatefulWidget {
  const AtlasShell({super.key});

  @override
  State<AtlasShell> createState() => _AtlasShellState();
}

class _AtlasShellState extends State<AtlasShell> {
  int index = 0;

  static const destinations = [
    NavigationDestination(
      icon: Icon(Icons.home_outlined),
      selectedIcon: Icon(Icons.home),
      label: 'Home',
    ),
    NavigationDestination(
      icon: Icon(Icons.menu_book_outlined),
      selectedIcon: Icon(Icons.menu_book),
      label: 'Notebooks',
    ),
    NavigationDestination(
      icon: Icon(Icons.search),
      label: 'Search',
    ),
    NavigationDestination(
      icon: Icon(Icons.cloud_outlined),
      selectedIcon: Icon(Icons.cloud),
      label: 'Cloud',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final pages = [
      const _PlaceholderPage(
        title: 'Atlas Notes',
        subtitle: 'Your cloud-first, offline-capable workspace.',
        icon: Icons.auto_stories_outlined,
      ),
      const _PlaceholderPage(
        title: 'Notebooks',
        subtitle: 'Notes, pages, folders and templates will live here.',
        icon: Icons.menu_book_outlined,
      ),
      const _PlaceholderPage(
        title: 'Search',
        subtitle: 'Fast deterministic search across your local index.',
        icon: Icons.search,
      ),
      const _PlaceholderPage(
        title: 'Cloud',
        subtitle: 'Sync, sharing and collaboration will live here.',
        icon: Icons.cloud_outlined,
      ),
    ];

    return Scaffold(
      appBar: AppBar(
        title: const Text('Atlas Notes'),
        actions: [
          IconButton(
            tooltip: 'New note',
            onPressed: () {},
            icon: const Icon(Icons.add),
          ),
        ],
      ),
      body: IndexedStack(index: index, children: pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: index,
        destinations: destinations,
        onDestinationSelected: (value) => setState(() => index = value),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {},
        icon: const Icon(Icons.edit),
        label: const Text('New note'),
      ),
    );
  }
}

class _PlaceholderPage extends StatelessWidget {
  const _PlaceholderPage({
    required this.title,
    required this.subtitle,
    required this.icon,
  });

  final String title;
  final String subtitle;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 64, color: Theme.of(context).colorScheme.primary),
              const SizedBox(height: 20),
              Text(title, style: Theme.of(context).textTheme.headlineMedium),
              const SizedBox(height: 8),
              Text(
                subtitle,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyLarge,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
