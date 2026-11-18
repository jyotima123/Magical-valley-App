import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:mvc_app/app_theme.dart';
import 'package:mvc_app/modules/cars/vehicle_image.dart';
import 'package:mvc_app/modules/cars/vehicle_inquiry_chat_screen.dart';
import 'package:mvc_app/modules/chat/widgets/image_carousel_screen.dart';
import 'package:mvc_app/modules/market/pets/petango_api_service.dart';
import 'package:mvc_app/modules/market/pets/shelter_animal.dart';
import 'package:mvc_app/services/api_repository.dart';

/// One shelter animal. Adopters message the shelter from here, in-app, the
/// way buyers message a dealership: the shelter's organization answers.
///
/// Opens straight away on what the shelter list already had, then fills in the
/// fee, description and remaining photos from the details call.
class ShelterAnimalDetailScreen extends StatefulWidget {
  final ShelterAnimal animal;
  final PetangoApiService? service;

  const ShelterAnimalDetailScreen({
    super.key,
    required this.animal,
    this.service,
  });

  @override
  State<ShelterAnimalDetailScreen> createState() =>
      _ShelterAnimalDetailScreenState();
}

class _ShelterAnimalDetailScreenState extends State<ShelterAnimalDetailScreen> {
  late final PetangoApiService _service = widget.service ?? PetangoApiService();
  final _pageCtrl = PageController();

  late ShelterAnimal _animal = widget.animal;
  bool _loadingDetails = true;

  /// The details call said the animal is gone — adopted since the list loaded.
  bool _noLongerListed = false;
  int _currentPage = 0;
  bool _startingChat = false;

  @override
  void initState() {
    super.initState();
    _loadDetails();
  }

  @override
  void dispose() {
    _pageCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadDetails() async {
    try {
      final full = await _service.fetchDetails(widget.animal);
      if (!mounted) return;
      setState(() => _animal = full);
      VehicleImageCache.prefetch(full.photos);
    } on PetangoException catch (e) {
      if (!mounted) return;
      // Anything else leaves the summary on screen, which is still accurate.
      if (e.statusCode == 404) setState(() => _noLongerListed = true);
    } finally {
      if (mounted) setState(() => _loadingDetails = false);
    }
  }

  Future<void> _openInquiryChat() async {
    setState(() => _startingChat = true);
    final result = await context
        .read<ApiRepository>()
        .createOrGetShelterAnimalInquiry(_animal);

    if (!mounted) return;
    setState(() => _startingChat = false);

    if (result.isSuccess && result.data != null) {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => VehicleInquiryChatScreen(conversation: result.data!),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result.error ?? 'Failed to start conversation'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      body: CustomScrollView(
        slivers: [
          _buildAppBar(),
          SliverToBoxAdapter(child: _buildContent()),
        ],
      ),
    );
  }

  /// Full-screen, zoomable view of the photos, opened on the tapped one.
  void _openPhotos(List<String> urls, int index) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ImageCarouselScreen(
          imageUrls: urls,
          initialIndex: index,
          theme: AppThemeMode.light,
        ),
      ),
    );
  }

  Widget _buildAppBar() {
    final photos = _animal.photos;
    return SliverAppBar(
      expandedHeight: photos.isNotEmpty ? 320 : 200,
      pinned: true,
      backgroundColor: AppTheme.headerBackground,
      foregroundColor: AppTheme.black,
      flexibleSpace: FlexibleSpaceBar(
        background: photos.isEmpty
            ? _photoPlaceholder()
            : Stack(
                fit: StackFit.expand,
                children: [
                  PageView.builder(
                    controller: _pageCtrl,
                    itemCount: photos.length,
                    onPageChanged: (i) => setState(() => _currentPage = i),
                    itemBuilder: (_, i) => GestureDetector(
                      onTap: () => _openPhotos(photos, i),
                      child: VehicleImage(
                        url: photos[i],
                        fit: BoxFit.cover,
                        alignment: Alignment.topCenter,
                        placeholder: (_) => _photoPlaceholder(),
                      ),
                    ),
                  ),
                  if (photos.length > 1)
                    Positioned(
                      bottom: 12,
                      left: 0,
                      right: 0,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: List.generate(
                          photos.length,
                          (i) => AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            margin: const EdgeInsets.symmetric(horizontal: 3),
                            width: _currentPage == i ? 20 : 6,
                            height: 6,
                            decoration: BoxDecoration(
                              color: _currentPage == i
                                  ? Colors.white
                                  : Colors.white54,
                              borderRadius: BorderRadius.circular(3),
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
      ),
    );
  }

  Widget _photoPlaceholder() {
    return Container(
      color: const Color(0xFFF0F0F0),
      child: Center(
        child: Icon(Icons.pets, size: 64, color: Colors.grey.shade300),
      ),
    );
  }

  Widget _buildContent() {
    final animal = _animal;
    final fee = animal.displayFee;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          color: Colors.white,
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (animal.onHold || fee != null) ...[
                Row(
                  children: [
                    if (animal.onHold) ...[
                      _Badge(
                        'On hold',
                        background: Colors.orange.withValues(alpha: 0.14),
                        foreground: Colors.orange.shade800,
                      ),
                      const SizedBox(width: 8),
                    ],
                    if (fee != null)
                      _Badge(
                        'Adoption fee $fee',
                        background: AppTheme.accentPrimary.withValues(
                          alpha: 0.14,
                        ),
                        foreground: AppTheme.accentPrimary,
                      ),
                  ],
                ),
                const SizedBox(height: 10),
              ],
              Text(
                animal.name,
                style: const TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.black,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                animal.summary,
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 14,
                  color: Colors.grey.shade600,
                ),
              ),
              if (animal.shelterName != null) ...[
                const SizedBox(height: 10),
                Row(
                  children: [
                    Icon(
                      Icons.location_on,
                      size: 14,
                      color: Colors.grey.shade400,
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        animal.shelterName!,
                        style: TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: 12,
                          color: Colors.grey.shade500,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 16),
              if (_noLongerListed)
                const _GoneNotice()
              else
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _startingChat ? null : _openInquiryChat,
                    icon: _startingChat
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.chat_bubble_outline, size: 18),
                    label: Text(_startingChat ? 'Opening…' : 'Message Shelter'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.accentPrimary,
                      foregroundColor: Colors.white,
                      disabledBackgroundColor: AppTheme.accentPrimary
                          .withValues(alpha: 0.6),
                      disabledForegroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      textStyle: const TextStyle(
                        fontFamily: 'Poppins',
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        if (animal.description != null)
          _Section(
            title: 'About ${animal.name}',
            child: Text(
              animal.description!,
              style: const TextStyle(
                fontFamily: 'Poppins',
                fontSize: 14,
                color: AppTheme.black,
                height: 1.5,
              ),
            ),
          ),
        _Section(
          title: 'Details',
          trailing: _loadingDetails
              ? const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: AppTheme.accentPrimary,
                  ),
                )
              : null,
          child: Column(
            children: [
              for (final (label, value) in _facts(animal))
                _FactRow(label: label, value: value),
            ],
          ),
        ),
        if (animal.notes.isNotEmpty)
          _Section(
            title: 'Good to know',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final note in animal.notes)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Row(
                      children: [
                        Icon(
                          Icons.info_outline,
                          size: 16,
                          color: Colors.grey.shade500,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            note,
                            style: const TextStyle(
                              fontFamily: 'Poppins',
                              fontSize: 14,
                              color: AppTheme.black,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        const SizedBox(height: 32),
      ],
    );
  }

  /// Only what the shelter actually filled in.
  static List<(String, String)> _facts(ShelterAnimal a) {
    return [
      ('Species', a.species),
      ('Breed', a.breedLabel),
      if (a.sex != null) ('Sex', a.sex!),
      if (a.ageGroup != null) ('Age', a.ageGroup!),
      if (a.size != null) ('Size', a.size!),
      if (a.colors.isNotEmpty) ('Color', a.colors.join(', ')),
      if (a.altered != null) ('Spayed / neutered', a.altered! ? 'Yes' : 'No'),
      if (a.housetrained != null) ('Housetrained', a.housetrained!),
      if (a.livedWithChildren != null)
        ('Lived with children', a.livedWithChildren!),
      if (a.livedWithAnimals != null)
        ('Lived with other animals', a.livedWithAnimals!),
    ];
  }
}

// ─── Sub-widgets ──────────────────────────────────────────────────────────────

class _Section extends StatelessWidget {
  final String title;
  final Widget? trailing;
  final Widget child;

  const _Section({required this.title, this.trailing, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(16),
      color: Colors.white,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.accentPrimary,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
              ?trailing,
            ],
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

class _FactRow extends StatelessWidget {
  final String label;
  final String value;

  const _FactRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 2,
            child: Text(
              label,
              style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: 13,
                color: Colors.grey.shade500,
              ),
            ),
          ),
          Expanded(
            flex: 3,
            child: Text(
              value,
              style: const TextStyle(
                fontFamily: 'Poppins',
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppTheme.black,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  final String label;
  final Color background;
  final Color foreground;

  const _Badge(
    this.label, {
    required this.background,
    required this.foreground,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontFamily: 'Poppins',
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: foreground,
        ),
      ),
    );
  }
}

class _GoneNotice extends StatelessWidget {
  const _GoneNotice();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        color: Colors.grey.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.grey.withValues(alpha: 0.25)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.favorite, size: 16, color: Colors.grey.shade500),
          const SizedBox(width: 8),
          Text(
            'No longer listed — likely adopted',
            style: TextStyle(
              fontFamily: 'Poppins',
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: Colors.grey.shade600,
            ),
          ),
        ],
      ),
    );
  }
}
