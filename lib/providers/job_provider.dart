import 'package:flutter/material.dart';
import '../backendless_client.dart';
import '../models/models.dart';

class JobProvider extends ChangeNotifier {
  List<Job> _jobs       = [];
  bool      _isLoading  = false;
  String?   _error;
  String    _searchQuery = '';
  PetType?  _filterType;

  List<Job> get jobs       => _jobs;
  bool      get isLoading  => _isLoading;
  String?   get error      => _error;
  String    get searchQuery => _searchQuery;
  PetType?  get filterType  => _filterType;

  // Filtered view used by HomeScreen ListView
  List<Job> get filteredJobs {
    var list = _jobs.where((j) => j.status.isActive).toList();
    if (_filterType != null) {
      list = list.where((j) => j.petType == _filterType).toList();
    }
    if (_searchQuery.isNotEmpty) {
      final q = _searchQuery.toLowerCase();
      list = list.where((j) =>
        j.title.toLowerCase().contains(q) ||
        (j.breedName?.toLowerCase().contains(q) ?? false) ||
        j.location.address.toLowerCase().contains(q),
      ).toList();
    }
    return list;
  }

  Future<void> fetchJobs() async {
    _isLoading = true;
    _error     = null;
    notifyListeners();
    try {
      final raw = await BackendlessClient.instance.find(
        'Jobs',
        sortBy:   'created DESC',
        pageSize: 50,
      );
      debugPrint('[JobProvider] fetched ${raw.length} raw records');
      final jobs = <Job>[];
      for (var i = 0; i < raw.length; i++) {
        try {
          jobs.add(Job.fromJson(raw[i]));
        } catch (e, st) {
          debugPrint('[JobProvider] Job.fromJson failed on record $i: $e');
          debugPrint('[JobProvider] record $i keys: ${raw[i].keys.toList()}');
          debugPrint('[JobProvider] location raw: ${raw[i]['location']}');
          debugPrint('[JobProvider] stacktrace: $st');
        }
      }
      _jobs = jobs;
      debugPrint('[JobProvider] parsed ${_jobs.length} jobs successfully');
    } catch (e, st) {
      debugPrint('[JobProvider] fetchJobs error: $e');
      debugPrint('[JobProvider] stacktrace: $st');
      _error = 'Could not load jobs. Check your connection.';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  void setSearch(String query) {
    _searchQuery = query;
    notifyListeners();
  }

  void setFilter(PetType? type) {
    _filterType = type;
    notifyListeners();
  }

  void clearFilters() {
    _searchQuery = '';
    _filterType  = null;
    notifyListeners();
  }
}