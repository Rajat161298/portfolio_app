import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:http/http.dart' as http;

void main() => runApp(PortfolioApp());

class PortfolioApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Portfolio Management Suite',
      theme: ThemeData(
        primarySwatch: Colors.indigo,
        visualDensity: VisualDensity.adaptivePlatformDensity,
        cardTheme: CardTheme(
          elevation: 4,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            padding: EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          ),
        ),
      ),
      home: HomeScreen(),
      debugShowCheckedModeBanner: false,
    );
  }
}

String backendHost({int port = 5000}) {
  // GitPod detection
  if (kIsWeb) {
    final currentUrl = Uri.base;
    if (currentUrl.host.contains('gitpod.io')) {
      // GitPod workspace URL pattern
      final workspaceUrl = currentUrl.host.replaceAll('8080-', '$port-');
      return 'https://$workspaceUrl';
    }
    return 'http://localhost:$port';
  }
  
  // Mobile/Desktop
  var host = '127.0.0.1';
  try {
    if (!kIsWeb && Platform.isAndroid) {
      host = '10.0.2.2';
    }
  } catch (e) {}
  return 'http://$host:$port';
}

class HomeScreen extends StatefulWidget {
  @override
  _HomeScreenState createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _index = 0;
  final _screens = [HoldingsAnalyzerScreen(), OptimizerScreen()];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _index, children: _screens),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _index,
        onTap: (i) => setState(() => _index = i),
        type: BottomNavigationBarType.fixed,
        selectedItemColor: Colors.indigo,
        unselectedItemColor: Colors.grey,
        items: [
          BottomNavigationBarItem(
            icon: Icon(Icons.account_balance_wallet),
            label: 'My Holdings',
            tooltip: 'Analyze your current portfolio holdings',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.trending_up),
            label: 'Optimizer',
            tooltip: 'Optimize portfolio allocation',
          ),
        ],
      ),
    );
  }
}

// ---------------- Holdings Analyzer Screen (Updated Feature 1) ----------------
class HoldingsAnalyzerScreen extends StatefulWidget {
  @override
  _HoldingsAnalyzerScreenState createState() => _HoldingsAnalyzerScreenState();
}

class _HoldingsAnalyzerScreenState extends State<HoldingsAnalyzerScreen> {
  bool loading = false;
  Map<String, dynamic> results = {};
  String get uploadUrl => backendHost(port: 5000) + '/upload';

  Future<void> pickAndUploadCSV() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['csv'],
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;

    setState(() => loading = true);
    try {
      final bytes = result.files.single.bytes!;
      final req = http.MultipartRequest('POST', Uri.parse(uploadUrl));
      req.files.add(http.MultipartFile.fromBytes(
        'file', 
        bytes, 
        filename: result.files.single.name
      ));
      
      final streamed = await req.send();
      final resp = await http.Response.fromStream(streamed);

      if (resp.statusCode == 200) {
        final body = json.decode(resp.body);
        setState(() {
          results = Map<String, dynamic>.from(body);
        });
        _showSuccessSnackBar('Portfolio analyzed with live market prices!');
      } else {
        final msg = resp.body.isNotEmpty ? resp.body : 'Server error ${resp.statusCode}';
        _showErrorSnackBar(msg);
      }
    } catch (e) {
      _showErrorSnackBar('Upload error: $e');
    } finally {
      setState(() => loading = false);
    }
  }

  void _showSuccessSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.green,
        duration: Duration(seconds: 3),
      ),
    );
  }

  void _showErrorSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
        action: SnackBarAction(
          label: 'Dismiss',
          textColor: Colors.white,
          onPressed: () {},
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final portfolioValue = ((results['portfolioValue'] ?? 0) as num).toDouble();
    final totalInvested = ((results['totalInvested'] ?? 0) as num).toDouble();
    final totalGainLoss = ((results['totalGainLoss'] ?? 0) as num).toDouble();
    final totalReturn = ((results['totalReturn'] ?? 0) as num).toDouble();
    final unmapped = (results['unmappedTickers'] ?? []) as List<dynamic>;
    final pricesFetched = (results['pricesFetched'] ?? 0) as int;
    final totalHoldings = (results['totalHoldings'] ?? 0) as int;

    return Scaffold(
      appBar: AppBar(
        title: Text('My Portfolio Holdings'),
        elevation: 0,
        backgroundColor: Colors.indigo,
        foregroundColor: Colors.white,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Portfolio Summary Cards
              Row(
                children: [
                  Expanded(
                    child: Card(
                      color: Colors.blue.shade50,
                      child: Padding(
                        padding: EdgeInsets.all(16),
                        child: Column(
                          children: [
                            Icon(Icons.account_balance_wallet, 
                                 size: 28, color: Colors.blue),
                            SizedBox(height: 8),
                            Text(
                              'Current Value',
                              style: TextStyle(fontSize: 14, color: Colors.grey[700]),
                            ),
                            SizedBox(height: 4),
                            Text(
                              '₹${portfolioValue.toStringAsFixed(0)}',
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                                color: Colors.blue,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  SizedBox(width: 12),
                  Expanded(
                    child: Card(
                      color: Colors.orange.shade50,
                      child: Padding(
                        padding: EdgeInsets.all(16),
                        child: Column(
                          children: [
                            Icon(Icons.savings, 
                                 size: 28, color: Colors.orange),
                            SizedBox(height: 8),
                            Text(
                              'Total Invested',
                              style: TextStyle(fontSize: 14, color: Colors.grey[700]),
                            ),
                            SizedBox(height: 4),
                            Text(
                              '₹${totalInvested.toStringAsFixed(0)}',
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                                color: Colors.orange,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              
              SizedBox(height: 12),
              
              // Gain/Loss Summary Card
              Card(
                color: totalGainLoss >= 0 ? Colors.green.shade50 : Colors.red.shade50,
                child: Padding(
                  padding: EdgeInsets.all(20),
                  child: Row(
                    children: [
                      Icon(
                        totalGainLoss >= 0 ? Icons.trending_up : Icons.trending_down,
                        size: 32, 
                        color: totalGainLoss >= 0 ? Colors.green : Colors.red,
                      ),
                      SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              totalGainLoss >= 0 ? 'Total Profit' : 'Total Loss',
                              style: TextStyle(fontSize: 16, color: Colors.grey[700]),
                            ),
                            SizedBox(height: 4),
                            Text(
                              '₹${totalGainLoss.abs().toStringAsFixed(0)}',
                              style: TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.bold,
                                color: totalGainLoss >= 0 ? Colors.green : Colors.red,
                              ),
                            ),
                            Text(
                              '${totalGainLoss >= 0 ? '+' : '-'}${(totalReturn * 100).abs().toStringAsFixed(2)}%',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w600,
                                color: totalGainLoss >= 0 ? Colors.green.shade700 : Colors.red.shade700,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              
              SizedBox(height: 20),
              
              // Upload Button
              Container(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: loading ? null : pickAndUploadCSV,
                  icon: loading 
                    ? SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : Icon(Icons.upload_file),
                  label: Text(
                    loading ? 'Fetching Live Market Prices...' : 'Upload Current Holdings CSV',
                    style: TextStyle(fontSize: 16),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.indigo,
                    foregroundColor: Colors.white,
                    padding: EdgeInsets.symmetric(vertical: 16),
                  ),
                ),
              ),

              // Upload Instructions
              if (results.isEmpty) ...[
                SizedBox(height: 16),
                Container(
                  padding: EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.blue.shade200),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.info_outline, color: Colors.blue, size: 24),
                          SizedBox(width: 8),
                          Text(
                            'CSV Format Required:',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Colors.blue.shade800,
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: 12),
                      Container(
                        padding: EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.blue.shade100),
                        ),
                        child: Text(
                          'Ticker, EntryDate, EntryPrice, Quantity\nRELIANCE.NS, 2024-01-15, 2500.00, 10\nTCS.NS, 2024-02-01, 3200.00, 5\nINFY.NS, 2024-01-20, 1400.00, 15',
                          style: TextStyle(
                            fontFamily: 'Courier',
                            fontSize: 12,
                            color: Colors.blue.shade800,
                          ),
                        ),
                      ),
                      SizedBox(height: 12),
                      Row(
                        children: [
                          Icon(Icons.speed, color: Colors.blue, size: 20),
                          SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Live market prices from Yahoo Finance',
                              style: TextStyle(
                                color: Colors.blue.shade700, 
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: 4),
                      Row(
                        children: [
                          Icon(Icons.analytics, color: Colors.blue, size: 20),
                          SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Automatic gain/loss calculation',
                              style: TextStyle(
                                color: Colors.blue.shade700, 
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: 4),
                      Row(
                        children: [
                          Icon(Icons.pie_chart, color: Colors.blue, size: 20),
                          SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Real-time sector & asset allocation',
                              style: TextStyle(
                                color: Colors.blue.shade700, 
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],

              // Status Information
              if (results.isNotEmpty) ...[
                SizedBox(height: 16),
                Container(
                  padding: EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.green.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.green.shade200),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.check_circle, color: Colors.green, size: 24),
                      SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Live Analysis Complete',
                              style: TextStyle(
                                color: Colors.green.shade800,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Text(
                              '$pricesFetched of $totalHoldings stocks updated with current market prices',
                              style: TextStyle(
                                color: Colors.green.shade700,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              // Unmapped Tickers Warning
              if (unmapped.isNotEmpty) ...[
                SizedBox(height: 16),
                Container(
                  padding: EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.orange.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.orange.shade200),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.warning_amber, color: Colors.orange, size: 24),
                      SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Missing Sector Information',
                              style: TextStyle(
                                color: Colors.orange.shade800,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Text(
                              'These tickers need sector mapping: ${unmapped.join(', ')}',
                              style: TextStyle(
                                color: Colors.orange.shade700,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              // Results Section
              if (results.isNotEmpty) ...[
                SizedBox(height: 24),
                
                // Top Performers Section
                Row(
                  children: [
                    Icon(Icons.trending_up, color: Colors.indigo, size: 24),
                    SizedBox(width: 8),
                    Text(
                      'Top Performers (Live Prices)',
                      style: TextStyle(
                        fontSize: 20, 
                        fontWeight: FontWeight.bold,
                        color: Colors.indigo,
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 12),
                
                Row(
                  children: [
                    Expanded(
                      child: _performanceTable(
                        'Top Gainers',
                        (results['topGainers'] ?? []).cast<dynamic>(),
                        Colors.green,
                        Icons.trending_up,
                      ),
                    ),
                    SizedBox(width: 12),
                    Expanded(
                      child: _performanceTable(
                        'Worst Performers',
                        (results['topLosers'] ?? []).cast<dynamic>(),
                        Colors.red,
                        Icons.trending_down,
                      ),
                    ),
                  ],
                ),

                SizedBox(height: 24),
                
                // Portfolio Composition
                Row(
                  children: [
                    Icon(Icons.pie_chart, color: Colors.indigo, size: 24),
                    SizedBox(width: 8),
                    Text(
                      'Portfolio Composition (Current Value)',
                      style: TextStyle(
                        fontSize: 20, 
                        fontWeight: FontWeight.bold,
                        color: Colors.indigo,
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 12),
                
                Card(
                  child: Padding(
                    padding: EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _allocationSection(
                          'Asset Allocation',
                          results['assetAllocation'] ?? {},
                          Icons.account_balance,
                        ),
                        SizedBox(height: 16),
                        Divider(thickness: 1),
                        SizedBox(height: 16),
                        _allocationSection(
                          'Sector Exposure',
                          results['sectorExposure'] ?? {},
                          Icons.domain,
                        ),
                      ],
                    ),
                  ),
                ),

                // Individual Holdings Details
                if (results['portfolioDetails'] != null) ...[
                  SizedBox(height: 24),
                  
                  Row(
                    children: [
                      Icon(Icons.list_alt, color: Colors.indigo, size: 24),
                      SizedBox(width: 8),
                      Text(
                        'Individual Holdings Performance',
                        style: TextStyle(
                          fontSize: 20, 
                          fontWeight: FontWeight.bold,
                          color: Colors.indigo,
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: 12),
                  
                  _buildHoldingsTable(results['portfolioDetails']),
                ],
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _performanceTable(String title, List<dynamic> data, Color color, IconData icon) {
    return Card(
      elevation: 6,
      child: Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              children: [
                Icon(icon, color: color, size: 20),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(
                      fontWeight: FontWeight.bold, 
                      fontSize: 16,
                      color: color,
                    ),
                  ),
                ),
              ],
            ),
            SizedBox(height: 12),
            if (data.isEmpty)
              Container(
                padding: EdgeInsets.all(20),
                child: Column(
                  children: [
                    Icon(Icons.info_outline, color: Colors.grey, size: 32),
                    SizedBox(height: 8),
                    Text(
                      'No ${title.toLowerCase()} found',
                      style: TextStyle(color: Colors.grey, fontSize: 14),
                    ),
                  ],
                ),
              )
            else
              ...data.take(5).map((item) => Container(
                margin: EdgeInsets.symmetric(vertical: 4),
                padding: EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        item[0].toString(),
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: color.withOpacity(0.9),
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Container(
                      padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: color,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        '${((item[1] as num) * 100).toStringAsFixed(1)}%',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ),
              )),
          ],
        ),
      ),
    );
  }

  Widget _allocationSection(String title, Map<String, dynamic> data, IconData icon) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, color: Colors.indigo, size: 20),
            SizedBox(width: 8),
            Text(
              title,
              style: TextStyle(
                fontWeight: FontWeight.bold, 
                fontSize: 16,
                color: Colors.indigo,
              ),
            ),
          ],
        ),
        SizedBox(height: 12),
        if (data.isEmpty)
          Text(
            'No allocation data available', 
            style: TextStyle(color: Colors.grey, fontSize: 14),
          )
        else
          ...data.entries.map((entry) => Container(
            margin: EdgeInsets.symmetric(vertical: 4),
            padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.indigo.withOpacity(0.05),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.indigo.withOpacity(0.1)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  entry.key,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Container(
                  padding: EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.indigo.shade600,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '${((entry.value as num) * 100).toStringAsFixed(1)}%',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
          )),
      ],
    );
  }

  Widget _buildHoldingsTable(List<dynamic> holdings) {
    return Card(
      elevation: 6,
      child: Column(
        children: [
          Container(
            padding: EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [Colors.indigo.shade600, Colors.indigo.shade400],
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
              ),
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(12),
                topRight: Radius.circular(12),
              ),
            ),
            child: Row(
              children: [
                Expanded(flex: 3, child: Text('Stock', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white))),
                Expanded(flex: 2, child: Text('Entry ₹', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white))),
                Expanded(flex: 2, child: Text('Current ₹', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white))),
                Expanded(flex: 2, child: Text('P&L', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white))),
              ],
            ),
          ),
          Container(
            constraints: BoxConstraints(maxHeight: 400),
            child: SingleChildScrollView(
              child: Column(
                children: holdings.asMap().entries.map((entry) {
                  final idx = entry.key;
                  final holding = entry.value;
                  final gainLossPct = (holding['gain_loss_pct'] ?? 0.0) as num;
                  final gainLossAmount = (holding['gain_loss'] ?? 0.0) as num;
                  
                  return Container(
                    padding: EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: idx % 2 == 0 ? Colors.white : Colors.grey.shade50,
                      border: Border(
                        bottom: BorderSide(color: Colors.grey.shade200, width: 1),
                      ),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          flex: 3,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                holding['ticker']?.toString() ?? '',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13,
                                ),
                              ),
                              Text(
                                'Qty: ${(holding['quantity'] ?? 0).toStringAsFixed(0)}',
                                style: TextStyle(
                                  fontSize: 11, 
                                  color: Colors.grey[600],
                                ),
                              ),
                            ],
                          ),
                        ),
                        Expanded(
                          flex: 2,
                          child: Text(
                            '${((holding['entry_price'] ?? 0) as num).toStringAsFixed(1)}',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        Expanded(
                          flex: 2,
                          child: Text(
                            '${((holding['current_price'] ?? 0) as num).toStringAsFixed(1)}',
                            style: TextStyle(
                              fontSize: 12, 
                              fontWeight: FontWeight.bold,
                              color: Colors.indigo,
                            ),
                          ),
                        ),
                        Expanded(
                          flex: 2,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Container(
                                padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: gainLossPct >= 0 ? Colors.green.shade100 : Colors.red.shade100,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  '${gainLossPct >= 0 ? '+' : ''}${gainLossPct.toStringAsFixed(1)}%',
                                  style: TextStyle(
                                    color: gainLossPct >= 0 ? Colors.green.shade800 : Colors.red.shade800,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 11,
                                  ),
                                ),
                              ),
                              SizedBox(height: 2),
                              Text(
                                '₹${gainLossAmount.toStringAsFixed(0)}',
                                style: TextStyle(
                                  color: gainLossAmount >= 0 ? Colors.green.shade700 : Colors.red.shade700,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  );
                }).toList(),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------- Portfolio Optimizer Screen (Feature 2 - Unchanged) ----------------
class OptimizerScreen extends StatefulWidget {
  @override
  _OptimizerScreenState createState() => _OptimizerScreenState();
}

class _OptimizerScreenState extends State<OptimizerScreen> {
  String get base => backendHost(port: 5000);

  List<String> sectors = [];
  List<String> assetClasses = [];
  Set<String> selSectors = {};
  Set<String> selClasses = {};
  int numStocks = 10;
  String objective = 'sharpe';

  bool loading = false;
  bool filtersLoading = true;
  Map<String, dynamic> metrics = {};
  List<dynamic> weightTable = [];
  Map<String, dynamic> benchmark = {};

  @override
  void initState() {
    super.initState();
    _fetchFilters();
  }

  Future<void> _fetchFilters() async {
    setState(() => filtersLoading = true);
    try {
      final sResp = await http.get(Uri.parse('$base/sectors'));
      final aResp = await http.get(Uri.parse('$base/asset_classes'));
      
      if (sResp.statusCode == 200) {
        final sectorsList = List<String>.from(json.decode(sResp.body));
        setState(() {
          sectors = sectorsList;
          if (sectors.isNotEmpty) selSectors = {sectors.first};
        });
      }
      
      if (aResp.statusCode == 200) {
        final classesList = List<String>.from(json.decode(aResp.body));
        setState(() {
          assetClasses = classesList;
          if (assetClasses.isNotEmpty) selClasses = {assetClasses.first};
        });
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to load filters: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      setState(() => filtersLoading = false);
    }
  }

  Future<void> _generate() async {
    if (selSectors.isEmpty || selClasses.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Please select at least one sector and asset class'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() => loading = true);
    final body = {
      'sectors': selSectors.toList(),
      'asset_classes': selClasses.toList(),
      'num_stocks': numStocks,
      'objective': objective,
    };
    
    try {
      final resp = await http.post(
        Uri.parse('$base/optimize'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode(body),
      );
      
      if (resp.statusCode == 200) {
        final r = json.decode(resp.body);
        setState(() {
          metrics = Map<String, dynamic>.from(r['metrics'] ?? {});
          weightTable = (r['weight_table'] ?? []).cast<dynamic>();
          benchmark = Map<String, dynamic>.from(r['benchmark_returns'] ?? {});
        });
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Portfolio optimization completed!'),
            backgroundColor: Colors.green,
          ),
        );
      } else {
        final errorMsg = json.decode(resp.body)['error'] ?? 'Optimization failed';
        throw Exception(errorMsg);
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      setState(() => loading = false);
    }
  }

  Widget _metricCard(String label, String value, {Color? valueColor, IconData? icon}) {
    return Card(
      elevation: 6,
      child: Container(
        padding: EdgeInsets.all(16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          gradient: LinearGradient(
            colors: [Colors.white, Colors.grey.shade50],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, color: valueColor ?? Colors.indigo, size: 28),
              SizedBox(height: 8),
            ],
            Text(
              label,
              style: TextStyle(
                fontSize: 14, 
                color: Colors.grey[600],
                fontWeight: FontWeight.w600,
              ),
              textAlign: TextAlign.center,
            ),
            SizedBox(height: 8),
            Text(
              value,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: valueColor ?? Colors.indigo,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Portfolio Optimizer'),
        elevation: 0,
        flexibleSpace: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [Colors.indigo.shade600, Colors.indigo.shade400],
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
            ),
          ),
        ),
        foregroundColor: Colors.white,
      ),
      body: filtersLoading
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(color: Colors.indigo),
                  SizedBox(height: 16),
                  Text(
                    'Loading optimization parameters...',
                    style: TextStyle(color: Colors.indigo, fontSize: 16),
                  ),
                ],
              ),
            )
          : SafeArea(
              child: SingleChildScrollView(
                padding: EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Configuration Section
                    Row(
                      children: [
                        Icon(Icons.settings, color: Colors.indigo, size: 24),
                        SizedBox(width: 8),
                        Text(
                          'Optimization Parameters',
                          style: TextStyle(
                            fontSize: 20, 
                            fontWeight: FontWeight.bold,
                            color: Colors.indigo,
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: 16),
                    
                    Card(
                      elevation: 6,
                      child: Padding(
                        padding: EdgeInsets.all(20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Sectors Selection
                            Row(
                              children: [
                                Icon(Icons.domain, color: Colors.indigo, size: 20),
                                SizedBox(width: 8),
                                Text(
                                  'Select Sectors',
                                  style: TextStyle(
                                    fontSize: 16, 
                                    fontWeight: FontWeight.w600,
                                    color: Colors.indigo,
                                  ),
                                ),
                              ],
                            ),
                            SizedBox(height: 12),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: sectors.map((s) {
                                final sel = selSectors.contains(s);
                                return FilterChip(
                                  label: Text(s),
                                  selected: sel,
                                  selectedColor: Colors.indigo.shade100,
                                  checkmarkColor: Colors.indigo,
                                  backgroundColor: Colors.grey.shade100,
                                  onSelected: (v) => setState(() {
                                    v ? selSectors.add(s) : selSectors.remove(s);
                                  }),
                                );
                              }).toList(),
                            ),
                            
                            SizedBox(height: 20),
                            
                            // Asset Classes Selection
                            Row(
                              children: [
                                Icon(Icons.account_balance, color: Colors.indigo, size: 20),
                                SizedBox(width: 8),
                                Text(
                                  'Select Asset Classes',
                                  style: TextStyle(
                                    fontSize: 16, 
                                    fontWeight: FontWeight.w600,
                                    color: Colors.indigo,
                                  ),
                                ),
                              ],
                            ),
                            SizedBox(height: 12),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: assetClasses.map((a) {
                                final sel = selClasses.contains(a);
                                return FilterChip(
                                  label: Text(a),
                                  selected: sel,
                                  selectedColor: Colors.indigo.shade100,
                                  checkmarkColor: Colors.indigo,
                                  backgroundColor: Colors.grey.shade100,
                                  onSelected: (v) => setState(() {
                                    v ? selClasses.add(a) : selClasses.remove(a);
                                  }),
                                );
                              }).toList(),
                            ),
                            
                            SizedBox(height: 20),
                            
                            // Number of Stocks Slider
                            Row(
                              children: [
                                Icon(Icons.format_list_numbered, color: Colors.indigo, size: 20),
                                SizedBox(width: 8),
                                Text(
                                  'Number of Stocks: $numStocks',
                                  style: TextStyle(
                                    fontSize: 16, 
                                    fontWeight: FontWeight.w600,
                                    color: Colors.indigo,
                                  ),
                                ),
                              ],
                            ),
                            SizedBox(height: 8),
                            Container(
                              decoration: BoxDecoration(
                                color: Colors.indigo.shade50,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                              child: Slider(
                                value: numStocks.toDouble(),
                                min: 2,
                                max: 50,
                                divisions: 48,
                                label: '$numStocks',
                                activeColor: Colors.indigo,
                                inactiveColor: Colors.indigo.shade200,
                                onChanged: (v) => setState(() => numStocks = v.toInt()),
                              ),
                            ),
                            
                            SizedBox(height: 20),
                            
                            // Optimization Objective Selection
                            Row(
                              children: [
                                Icon(Icons.target, color: Colors.indigo, size: 20),
                                SizedBox(width: 8),
                                Text(
                                  'Optimization Objective',
                                  style: TextStyle(
                                    fontSize: 16, 
                                    fontWeight: FontWeight.w600,
                                    color: Colors.indigo,
                                  ),
                                ),
                              ],
                            ),
                            SizedBox(height: 12),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                {'key': 'sharpe', 'label': 'Max Sharpe Ratio', 'icon': Icons.star, 'desc': 'Best risk-adjusted returns'},
                                {'key': 'vol', 'label': 'Min Risk', 'icon': Icons.shield, 'desc': 'Lowest volatility'},
                                {'key': 'mdd', 'label': 'Min Drawdown', 'icon': Icons.trending_down, 'desc': 'Smallest losses'},
                              ].map((o) {
                                final isSelected = objective == o['key'];
                                return GestureDetector(
                                  onTap: () => setState(() => objective = o['key'] as String),
                                  child: Container(
                                    padding: EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      color: isSelected ? Colors.indigo : Colors.white,
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(
                                        color: isSelected ? Colors.indigo : Colors.grey.shade300,
                                        width: 2,
                                      ),
                                    ),
                                    child: Column(
                                      children: [
                                        Icon(
                                          o['icon'] as IconData,
                                          size: 24,
                                          color: isSelected ? Colors.white : Colors.indigo,
                                        ),
                                        SizedBox(height: 4),
                                        Text(
                                          o['label'] as String,
                                          style: TextStyle(
                                            fontWeight: FontWeight.bold,
                                            color: isSelected ? Colors.white : Colors.indigo,
                                            fontSize: 12,
                                          ),
                                        ),
                                        Text(
                                          o['desc'] as String,
                                          style: TextStyle(
                                            color: isSelected ? Colors.white70 : Colors.grey,
                                            fontSize: 10,
                                          ),
                                          textAlign: TextAlign.center,
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              }).toList(),
                            ),
                          ],
                        ),
                      ),
                    ),
                    
                    SizedBox(height: 20),
                    
                    // Generate Button
                    Container(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: loading ? null : _generate,
                        child: Container(
                          padding: EdgeInsets.symmetric(vertical: 16),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              if (loading) ...[
                                SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                ),
                                SizedBox(width: 12),
                                Text(
                                  'Optimizing Portfolio...',
                                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                                ),
                              ] else ...[
                                Icon(Icons.auto_awesome, size: 24),
                                SizedBox(width: 12),
                                Text(
                                  'Generate Optimal Portfolio',
                                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                                ),
                              ],
                            ],
                          ),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.indigo,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ),
                    
                    // Results Section
                    if (metrics.isNotEmpty) ...[
                      SizedBox(height: 30),
                      
                      Row(
                        children: [
                          Icon(Icons.analytics, color: Colors.indigo, size: 24),
                          SizedBox(width: 8),
                          Text(
                            'Optimization Results',
                            style: TextStyle(
                              fontSize: 20, 
                              fontWeight: FontWeight.bold,
                              color: Colors.indigo,
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: 16),
                      
                      // Performance Metrics
                      GridView.count(
                        shrinkWrap: true,
                        physics: NeverScrollableScrollPhysics(),
                        crossAxisCount: 3,
                        mainAxisSpacing: 12,
                        crossAxisSpacing: 12,
                        childAspectRatio: 1.1,
                        children: [
                          _metricCard(
                            'Annual Return',
                            '${((metrics['annualized_return'] ?? 0.0) * 100).toStringAsFixed(1)}%',
                            valueColor: Colors.green,
                            icon: Icons.trending_up,
                          ),
                          _metricCard(
                            'Volatility',
                            '${((metrics['annualized_volatility'] ?? 0.0) * 100).toStringAsFixed(1)}%',
                            valueColor: Colors.orange,
                            icon: Icons.show_chart,
                          ),
                          _metricCard(
                            'Sharpe Ratio',
                            '${(metrics['sharpe'] ?? 0.0).toStringAsFixed(2)}',
                            valueColor: Colors.indigo,
                            icon: Icons.star,
                          ),
                        ],
                      ),
                    ],
                    
                    // Allocation Table
                    if (weightTable.isNotEmpty) ...[
                      SizedBox(height: 30),
                      
                      Row(
                        children: [
                          Icon(Icons.pie_chart, color: Colors.indigo, size: 24),
                          SizedBox(width: 8),
                          Text(
                            'Optimal Allocation',
                            style: TextStyle(
                              fontSize: 20, 
                              fontWeight: FontWeight.bold,
                              color: Colors.indigo,
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: 16),
                      
                      Card(
                        elevation: 6,
                        child: Column(
                          children: [
                            Container(
                              padding: EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [Colors.indigo.shade600, Colors.indigo.shade400],
                                  begin: Alignment.centerLeft,
                                  end: Alignment.centerRight,
                                ),
                                borderRadius: BorderRadius.only(
                                  topLeft: Radius.circular(12),
                                  topRight: Radius.circular(12),
                                ),
                              ),
                              child: Row(
                                children: [
                                  Expanded(flex: 3, child: Text('Stock', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 16))),
                                  Expanded(flex: 2, child: Text('Sector', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 16))),
                                  Expanded(flex: 2, child: Text('Weight', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 16))),
                                ],
                              ),
                            ),
                            ...weightTable.asMap().entries.map((entry) {
                              final idx = entry.key;
                              final r = entry.value;
                              final weight = ((r['weight'] ?? 0.0) * 100);
                              return Container(
                                padding: EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  color: idx % 2 == 0 ? Colors.white : Colors.grey.shade50,
                                  border: Border(
                                    bottom: BorderSide(color: Colors.grey.shade200, width: 1),
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    Expanded(
                                      flex: 3,
                                      child: Text(
                                        r['symbol'] ?? r['ticker'] ?? '',
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 14,
                                        ),
                                      ),
                                    ),
                                    Expanded(
                                      flex: 2,
                                      child: Container(
                                        padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                        decoration: BoxDecoration(
                                          color: Colors.grey.shade200,
                                          borderRadius: BorderRadius.circular(8),
                                        ),
                                        child: Text(
                                          r['sector'] ?? 'Unknown',
                                          style: TextStyle(
                                            color: Colors.grey[700],
                                            fontSize: 12,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ),
                                    ),
                                    Expanded(
                                      flex: 2,
                                      child: Container(
                                        padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                        decoration: BoxDecoration(
                                          color: Colors.indigo.shade600,
                                          borderRadius: BorderRadius.circular(12),
                                        ),
                                        child: Text(
                                          '${weight.toStringAsFixed(1)}%',
                                          style: TextStyle(
                                            fontWeight: FontWeight.bold,
                                            color: Colors.white,
                                            fontSize: 14,
                                          ),
                                          textAlign: TextAlign.center,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            }).toList(),
                          ],
                        ),
                      ),
                    ],
                    
                    // Benchmark Comparison
                    if (benchmark.isNotEmpty) ...[
                      SizedBox(height: 30),
                      
                      Row(
                        children: [
                          Icon(Icons.compare_arrows, color: Colors.indigo, size: 24),
                          SizedBox(width: 8),
                          Text(
                            'Benchmark Comparison',
                            style: TextStyle(
                              fontSize: 20, 
                              fontWeight: FontWeight.bold,
                              color: Colors.indigo,
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: 16),
                      
                      Card(
                        elevation: 6,
                        child: Padding(
                          padding: EdgeInsets.all(16),
                          child: Column(
                            children: [
                              Container(
                                padding: EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: Colors.indigo.shade50,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Row(
                                  children: [
                                    Expanded(flex: 2, child: Text('Period', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.indigo, fontSize: 16))),
                                    Expanded(flex: 2, child: Text('Portfolio', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.indigo, fontSize: 16), textAlign: TextAlign.center)),
                                    Expanded(flex: 2, child: Text('Nifty', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.indigo, fontSize: 16), textAlign: TextAlign.center)),
                                    Expanded(flex: 2, child: Text('Alpha', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.indigo, fontSize: 16), textAlign: TextAlign.center)),
                                  ],
                                ),
                              ),
                              SizedBox(height: 12),
                              ...benchmark.entries.map((e) {
                                final val = e.value as Map;
                                final portfolio = val['Portfolio'];
                                final nifty = val['Nifty'];
                                final portfolioReturn = portfolio == null ? 0.0 : (portfolio * 100);
                                final niftyReturn = nifty == null ? 0.0 : (nifty * 100);
                                final alpha = portfolioReturn - niftyReturn;
                                
                                return Container(
                                  margin: EdgeInsets.symmetric(vertical: 4),
                                  padding: EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: Colors.grey.shade50,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Row(
                                    children: [
                                      Expanded(
                                        flex: 2,
                                        child: Text(
                                          e.key,
                                          style: TextStyle(
                                            fontWeight: FontWeight.w600,
                                            fontSize: 14,
                                          ),
                                        ),
                                      ),
                                      Expanded(
                                        flex: 2,
                                        child: Container(
                                          padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                          decoration: BoxDecoration(
                                            color: portfolioReturn >= 0 ? Colors.green.shade100 : Colors.red.shade100,
                                            borderRadius: BorderRadius.circular(6),
                                          ),
                                          child: Text(
                                            '${portfolioReturn.toStringAsFixed(2)}%',
                                            style: TextStyle(
                                              color: portfolioReturn >= 0 ? Colors.green.shade800 : Colors.red.shade800,
                                              fontWeight: FontWeight.bold,
                                              fontSize: 13,
                                            ),
                                            textAlign: TextAlign.center,
                                          ),
                                        ),
                                      ),
                                      Expanded(
                                        flex: 2,
                                        child: Container(
                                          padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                          decoration: BoxDecoration(
                                            color: niftyReturn >= 0 ? Colors.green.shade100 : Colors.red.shade100,
                                            borderRadius: BorderRadius.circular(6),
                                          ),
                                          child: Text(
                                            '${niftyReturn.toStringAsFixed(2)}%',
                                            style: TextStyle(
                                              color: niftyReturn >= 0 ? Colors.green.shade800 : Colors.red.shade800,
                                              fontWeight: FontWeight.bold,
                                              fontSize: 13,
                                            ),
                                            textAlign: TextAlign.center,
                                          ),
                                        ),
                                      ),
                                      Expanded(
                                        flex: 2,
                                        child: Container(
                                          padding: EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                                          decoration: BoxDecoration(
                                            color: alpha >= 0 ? Colors.green.shade600 : Colors.red.shade600,
                                            borderRadius: BorderRadius.circular(8),
                                          ),
                                          child: Text(
                                            '${alpha >= 0 ? '+' : ''}${alpha.toStringAsFixed(2)}%',
                                            style: TextStyle(
                                              color: Colors.white,
                                              fontWeight: FontWeight.bold,
                                              fontSize: 12,
                                            ),
                                            textAlign: TextAlign.center,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              }).toList(),
                            ],
                          ),
                        ),
                      ),
                    ],
                    
                    // Additional spacing at bottom
                    SizedBox(height: 40),
                  ],
                ),
              ),
            ),
    );
  }
}