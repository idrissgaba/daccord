import 'dart:async';
import 'package:bonfire/features/member/utils/member_display.dart';
import 'package:bonfire/shared/components/async_state_views.dart';
import 'package:bonfire/shared/components/dialog_title_bar.dart';
import 'package:bonfire/shared/components/self_hosting_dialog.dart';
import 'package:bonfire/shared/components/ticker_aware_circle_avatar.dart';
import 'package:bonfire/shared/utils/rest_result_ext.dart';
import 'package:bonfire/shared/utils/responsive_dialog.dart';

import 'package:accordkit/accordkit.dart';
import 'package:bonfire/features/authentication/repositories/accord_auth.dart';
import 'package:bonfire/features/server/models/accord_server.dart';
import 'package:bonfire/features/server/services/deep_link_navigation.dart';
import 'package:bonfire/features/server/views/add_server_dialog.dart';
import 'package:bonfire/features/settings/controllers/settings.dart';
import 'package:bonfire/theme/theme.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

part 'discovery/widgets.dart';

typedef AccordDiscoveryBrowse =
    Future<RestResult> Function({
      required String masterUrl,
      required String query,
      required String tag,
    });

const _invalidDirectoryResponse =
    'The server returned an invalid directory response';

/// The REST root the master-server directory is browsed against.
///
/// Every accordkit endpoint group takes bare paths and expects the `/api/v1`
/// prefix on its `AccordRest` base URL — including [DirectoryApi] — so the
/// master URL gets the same treatment `AccordClient` gives an instance via
/// `config.apiUrl()`.
@visibleForTesting
String accordDirectoryRestUrl(String masterUrl) =>
    AccordServer.normalizeBaseUrl(masterUrl) + AccordConfig.apiBasePath;

/// Performs the unauthenticated master-server directory request.
///
/// Kept behind a provider so discovery's asynchronous state handling can be
/// tested without making network requests.
final accordDiscoveryBrowseProvider = Provider<AccordDiscoveryBrowse>((ref) {
  return ({
    required String masterUrl,
    required String query,
    required String tag,
  }) async {
    // Mirror the reference client (`discovery_panel.gd`): an unauthenticated
    // AccordRest pointed at the MASTER server + DirectoryApi. AccordClient is
    // not used here because it would also open a gateway socket and a voice
    // manager against a server we only want one anonymous GET from — see
    // [accordDirectoryRestUrl] for why the base URL is shaped the way it is.
    final rest = AccordRest(accordDirectoryRestUrl(masterUrl));
    try {
      return await DirectoryApi(rest).browse(query: query, tag: tag);
    } finally {
      rest.close();
    }
  };
});

/// Opens the discovery panel: a searchable browser of public spaces the user
/// can join. Backed by the **master-server** directory (unauthenticated), so it
/// works before signing in to any instance. Mirrors the reference client's
/// `discovery_panel`.
Future<void> showAccordDiscovery(BuildContext context) {
  return showDialog<void>(
    context: context,
    builder: (_) => const _DiscoveryPanel(),
  );
}

class _DiscoveryPanel extends StatelessWidget {
  const _DiscoveryPanel();

  @override
  Widget build(BuildContext context) {
    final colors = BonfireThemeExtension.of(context);
    return Dialog(
      backgroundColor: colors.foreground,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ConstrainedBox(
        constraints: dialogConstraints(context, maxWidth: 560, maxHeight: 600),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 16, 12, 8),
              child: DialogTitleBar('Discover Servers', icon: Icons.explore),
            ),
            Expanded(
              child: AccordDiscoveryBody(
                // The dialog is modal, so hand off to Add-Server rather than
                // stacking a second dialog on top of this one.
                onManualConnect: () {
                  Navigator.of(context).pop();
                  showAddServerDialog(context);
                },
                // A listing that needs auth reopens as the Add-Server flow
                // pre-targeted at the listing's instance + space.
                onJoinRequiresAuth: (serverUrl, spaceId) {
                  Navigator.of(context).pop();
                  showAddServerDialog(
                    context,
                    initialUrl: serverUrl,
                    joinSpaceId: spaceId,
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

/// The searchable public-space browser (search box + tag filter + results),
/// reusable both as the standalone discovery dialog and inside the
/// Add-a-Server "Browse" tab.
///
/// Browsing always targets the **master server** (configured in settings,
/// default `https://master.daccord.gg`) and needs no authentication — each
/// listing carries its own `server_url`, so a single directory federates across
/// instances. Joining a listing for an instance you are not connected to needs
/// auth against that instance: [onJoinRequiresAuth] is invoked so the host can
/// drive the right flow (switch the Add-Server URL tab, or open it fresh).
class AccordDiscoveryBody extends ConsumerStatefulWidget {
  const AccordDiscoveryBody({
    super.key,
    this.onJoinRequiresAuth,
    this.onManualConnect,
  });

  /// Called when joining requires authenticating against `serverUrl` first
  /// (i.e. there is no live connection to that instance yet). `spaceId` is the
  /// directory listing's space to join once connected.
  final void Function(String serverUrl, String spaceId)? onJoinRequiresAuth;

  /// Called by the "Connect to a server by URL" footer. When omitted the footer
  /// falls back to the Add-Server dialog, which is the right destination
  /// everywhere except the signed-out login flow (it drives its own form).
  final VoidCallback? onManualConnect;

  @override
  ConsumerState<AccordDiscoveryBody> createState() =>
      _AccordDiscoveryBodyState();
}

class _AccordDiscoveryBodyState extends ConsumerState<AccordDiscoveryBody> {
  final _query = TextEditingController();
  Timer? _debounce;
  List<Map<String, dynamic>>? _listings;
  List<String> _tags = const [];
  String? _activeTag;
  final Set<String> _joining = {};
  String? _error;
  int _requestGeneration = 0;

  @override
  void initState() {
    super.initState();
    _startSearch();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _query.dispose();
    super.dispose();
  }

  String get _masterUrl => ref.read(settingsControllerProvider).masterServerUrl;

  void _onChanged(String _) {
    _startSearch(delay: const Duration(milliseconds: 400));
  }

  void _startSearch({Duration delay = Duration.zero}) {
    _debounce?.cancel();
    final request = _DiscoveryRequest(
      generation: ++_requestGeneration,
      masterUrl: _masterUrl,
      query: _query.text.trim(),
      tag: _activeTag,
    );
    setState(() {
      _listings = null;
      _error = null;
    });

    if (delay == Duration.zero) {
      unawaited(_search(request));
    } else {
      _debounce = Timer(delay, () => unawaited(_search(request)));
    }
  }

  Future<void> _search(_DiscoveryRequest request) async {
    RestResult result;
    try {
      result = await ref.read(accordDiscoveryBrowseProvider)(
        masterUrl: request.masterUrl,
        query: request.query,
        tag: request.tag ?? '',
      );
    } catch (_) {
      if (!mounted || request.generation != _requestGeneration) return;
      setState(() {
        _error = 'Failed to load directory';
        _listings = const [];
      });
      return;
    }
    if (!mounted || request.generation != _requestGeneration) return;

    final listings = result.ok ? _decodeListings(result.data) : null;

    setState(() {
      if (!result.ok) {
        _error = result.errorOr('Failed to load directory');
        _listings = const [];
        return;
      }
      if (listings == null) {
        _error = _invalidDirectoryResponse;
        _listings = const [];
        return;
      }
      _listings = listings;
      // Only refresh the tag bar from an unfiltered result, so filtering by a
      // tag doesn't collapse the bar to that single tag.
      if (request.tag == null) {
        final tags = <String>{};
        for (final l in _listings!) {
          for (final t in (l['tags'] as List? ?? const [])) {
            final s = t.toString().trim();
            if (s.isNotEmpty) tags.add(s);
          }
        }
        _tags = tags.toList()..sort();
      }
    });
  }

  List<Map<String, dynamic>>? _decodeListings(Object? data) {
    Object? payload;
    if (data is List) {
      payload = data;
    } else if (data is Map) {
      payload = data['spaces'] ?? data['results'] ?? data['data'];
    }
    if (payload is! List) return null;

    final listings = <Map<String, dynamic>>[];
    for (final item in payload) {
      if (item is! Map) return null;
      final listing = <String, dynamic>{};
      for (final entry in item.entries) {
        final key = entry.key;
        if (key is! String) return null;
        listing[key] = entry.value;
      }
      listings.add(listing);
    }
    return listings;
  }

  void _selectTag(String? tag) {
    setState(() => _activeTag = tag);
    _startSearch();
  }

  Future<void> _join(Map<String, dynamic> listing) async {
    final rawServerUrl = listing['server_url']?.toString() ?? '';
    final spaceId =
        listing['space_id']?.toString() ?? listing['id']?.toString() ?? '';
    if (rawServerUrl.isEmpty || spaceId.isEmpty) {
      setState(() => _error = 'This listing is missing its server details');
      return;
    }
    if (_joining.contains(spaceId)) return;
    setState(() => _joining.add(spaceId));
    try {
      final baseUrl = AccordServer.fromBaseUrl(rawServerUrl).baseUrl;
      final auth = ref.read(accordAuthProvider.notifier);
      final existingKey = await auth.ensureConnectionForBaseUrl(baseUrl);
      if (!mounted) return;
      // Only an absent saved account needs the host's credentials flow.
      if (existingKey == null) {
        final handler = widget.onJoinRequiresAuth;
        if (handler != null) {
          handler(baseUrl, spaceId);
        } else {
          showAddServerDialog(
            context,
            initialUrl: baseUrl,
            joinSpaceId: spaceId,
          );
        }
        return;
      }
      final outcome = await auth.joinOnConnection(
        existingKey,
        spaceId: spaceId,
      );
      if (!mounted) return;
      if (outcome.error != null) {
        setState(() => _error = outcome.error);
        return;
      }
      ref
          .read(pendingDeepLinkProvider.notifier)
          .hold(
            PendingDeepLinkDestination(
              serverBaseUrl: baseUrl,
              spaceId: outcome.spaceId,
            ),
          );
      auth.setActiveServer(existingKey);
      if (mounted) Navigator.of(context).maybePop();
    } catch (error) {
      if (mounted) setState(() => _error = 'Could not join: $error');
    } finally {
      if (mounted) setState(() => _joining.remove(spaceId));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = BonfireThemeExtension.of(context);
    final listings = _listings;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: TextField(
            controller: _query,
            onChanged: _onChanged,
            decoration: const InputDecoration(
              isDense: true,
              prefixIcon: Icon(Icons.search, size: 18),
              hintText: 'Search servers...',
              border: OutlineInputBorder(),
            ),
          ),
        ),
        if (_tags.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                _TagChip(
                  label: 'All',
                  selected: _activeTag == null,
                  onTap: () => _selectTag(null),
                ),
                for (final tag in _tags)
                  _TagChip(
                    label: tag,
                    selected: _activeTag == tag,
                    onTap: () => _selectTag(tag),
                  ),
              ],
            ),
          ),
        const SizedBox(height: 8),
        // Above the list, not inside its empty branch: a failed *join* leaves
        // the one visible listing on screen, and the error has to be visible
        // alongside it rather than swallowed (#292).
        if (_error != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: _DirectoryError(message: _error!),
          ),
        // [Flexible] + `shrinkWrap`, not [Expanded]: a one-listing directory
        // should not leave the footer marooned at the bottom of a tablet-sized
        // void. A long list still fills the space and scrolls under it.
        Flexible(
          child: listings == null
              ? const LoadingView()
              : ListView(
                  shrinkWrap: true,
                  padding: const EdgeInsets.all(12),
                  children: [
                    if (listings.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        child: Text(
                          'No servers found',
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodyMedium,
                        ),
                      ),
                    for (final listing in listings)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: _DiscoveryCard(
                          listing: listing,
                          colors: colors,
                          theme: theme,
                          joining: _joining.contains(
                            listing['space_id']?.toString() ??
                                listing['id']?.toString() ??
                                '',
                          ),
                          onJoin: () => _join(listing),
                        ),
                      ),
                    // A one-card directory reads as a broken feature unless we
                    // say why it is short. Only shown for an unfiltered browse —
                    // a search that matched nothing is a different story.
                    if (listings.length <= 2 &&
                        _query.text.trim().isEmpty &&
                        _activeTag == null)
                      const _SparseDirectoryNote(),
                  ],
                ),
        ),
        _ConnectFooter(onManualConnect: _manualConnect),
      ],
    );
  }

  void _manualConnect() {
    final handler = widget.onManualConnect;
    if (handler != null) {
      handler();
    } else {
      showAddServerDialog(context);
    }
  }
}
