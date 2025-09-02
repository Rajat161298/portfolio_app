import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:csv/csv.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import 'package:squarified_treemap/squarified_treemap.dart';

void main() => runApp(MaterialApp(debugShowCheckedModeBanner: false, home: PortfolioScreen()));

// ---------------- Data Models ----------------
class PriceData {
  final DateTime date;
  final Map<String, double> prices;
  PriceData(this.date, this.prices);
}

class MetaInfo {
  final Map<String, String> sector;
  final Map<String, String> assetClass;
  MetaInfo({required this.sector, required this.assetClass});
}

// ---------------- CSV Parser ----------------
Future<(List<PriceData>, MetaInfo)> parsePrices(File file) async {
  final content = await file.readAsString();
  final rows = const CsvToListConverter().convert(content);

  final headers = rows[0].map((e) => e.toString()).toList();

  final sectorRow = rows[1];
  final assetClassRow = rows[2];

  final sectorMap = <String, String>{};
  final assetClassMap = <String, String>{};

  for (int j = 1; j < headers.length; j++) {
    sectorMap[headers[j]] = sectorRow[j].toString();
    assetClassMap[headers[j]] = assetClassRow[j].toString();
  }

  final List<PriceData> data = [];
  for (int i = 3; i < rows.length; i++) {
    final date = DateFormat("yyyy-MM-dd").parse(rows[i][0].toString());
    final Map<String, double> prices = {};
    for (int j = 1; j < headers.length; j++) {
      prices[headers[j]] = double.tryParse(rows[i][j].toString()) ?? 0;
    }
    data.add(PriceData(date, prices));
  }

  return (data, MetaInfo(sector: sectorMap, assetClass: assetClassMap));
}

// ---------------- Analytics ----------------
Map<String, List<double>> computeDailyReturns(List<PriceData> data) {
  final Map<String, List<double>> returns = {};
  if (data.length < 2) return returns;

  final assets = data.first.prices.keys;
  for (var asset in assets) {
    returns[asset] = [];
  }

  for (int i = 1; i < data.length; i++) {
    for (var asset in assets) {
      final prev = data[i - 1].prices[asset]!;
      final curr = data[i].prices[asset]!;
      final r = (curr / prev) - 1;
      returns[asset]!.add(r);
    }
  }
  return returns;
}

Map<String, double> computeExpectedReturns(Map<String, List<double>> returns) {
  final Map<String, double> expReturns = {};
  returns.forEach((asset, rList) {
    if (rList.isNotEmpty) {
      final mean = rList.reduce((a, b) => a + b) / rList.length;
      expReturns[asset] = mean * 252;
    }
  });
  return expReturns;
}

Map<String, Map<String, double>> computeCovariance(Map<String, List<double>> returns) {
  final assets = returns.keys.toList();
  final covMatrix = <String, Map<String, double>>{};

  for (var a in assets) {
    covMatrix[a] = {};
    for (var b in assets) {
      final rA = returns[a]!;
      final rB = returns[b]!;
      final n = min(rA.length, rB.length);

      final meanA = rA.reduce((x, y) => x + y) / rA.length;
      final meanB = rB.reduce((x, y) => x + y) / rB.length;

      double cov = 0;
      for (int i = 0; i < n; i++) {
        cov += (rA[i] - meanA) * (rB[i] - meanB);
      }
      covMatrix[a]![b] = (cov / (n - 1)) * 252;
    }
  }
  return covMatrix;
}

Map<String, double> computeSectorExposure(List<PriceData> data, Map<String, String> sectorInfo) {
  if (data.isEmpty) return {};
  final lastDay = data.last;
  final total = lastDay.prices.values.fold(0.0, (a, b) => a + b);

  final Map<String, double> sectorExposure = {};
  lastDay.prices.forEach((asset, value) {
    final sector = sectorInfo[asset] ?? "Other";
    sectorExposure[sector] = (sectorExposure[sector] ?? 0) + (value / total);
  });
  return sectorExposure;
}

Map<String, double> computeAssetAllocation(List<PriceData> data, Map<String, String> assetClassInfo) {
  if (data.isEmpty) return {};
  final lastDay = data.last;
  final total = lastDay.prices.values.fold(0.0, (a, b) => a + b);

  final Map<String, double> allocation = {};
  lastDay.prices.forEach((asset, value) {
    final cls = assetClassInfo[asset] ?? "Other";
    allocation[cls] = (allocation[cls] ?? 0) + (value / total);
  });
  return allocation;
}

// ---------------- Optimizer ----------------
List<double> randomWeights(int n) {
  final rand = Random();
  final weights = List.generate(n, (_) => rand.nextDouble());
  final sum = weights.reduce((a, b) => a + b);
  return weights.map((w) => w / sum).toList();
}

Map<String, double> optimizePortfolio(
  Map<String, double> expReturns,
  Map<String, Map<String, double>> covMatrix, {
  double riskFreeRate = 0.02,
  int simulations = 2000,
}) {
  final assets = expReturns.keys.toList();
  final n = assets.length;

  Map<String, double> bestWeights = {};
  double bestSharpe = -999;

  final rand = Random();

  for (int i = 0; i < simulations; i++) {
    final weights = List.generate(n, (_) => rand.nextDouble());
    final sumW = weights.reduce((a, b) => a + b);
    final normW = weights.map((w) => w / sumW).toList();

    double portReturn = 0;
    for (int j = 0; j < n; j++) {
      portReturn += normW[j] * expReturns[assets[j]]!;
    }

    double portVar = 0;
    for (int j = 0; j < n; j++) {
      for (int k = 0; k < n; k++) {
        portVar += normW[j] * normW[k] * covMatrix[assets[j]]![assets[k]]!;
      }
    }
    final portStd = sqrt(portVar);
    final sharpe = (portReturn - riskFreeRate) / (portStd > 0 ? portStd : 1);

    if (sharpe > bestSharpe) {
      bestSharpe = sharpe;
      bestWeights = {for (int j = 0; j < n; j++) assets[j]: normW[j]};
    }
  }
  return bestWeights;
}

// ---------------- UI Screen ----------------
class PortfolioScreen extends StatefulWidget {
  @override
  _PortfolioScreenState createState() => _PortfolioScreenState();
}

class _PortfolioScreenState extends State<PortfolioScreen> {
  double portfolioValue = 0;
  Map<String, double> sectorExposure = {};
  Map<String, double> assetAllocation = {};
  Map<String, double> optimalWeights = {};
  List<FlSpot> efficientFrontier = [];
  FlSpot? myPortfolioPoint;

  List<MapEntry<String, double>> topGainers = [];
  List<MapEntry<String, double>> topLosers = [];

  bool hasData = false;

  Future<void> pickAndLoadCSV() async {
    final result = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['csv']);
    if (result != null && result.files.single.path != null) {
      final file = File(result.files.single.path!);
      final (priceData, meta) = await parsePrices(file);

      final lastDay = priceData.last;
      final totalValue = lastDay.prices.values.fold(0.0, (a, b) => a + b);

      final sector = computeSectorExposure(priceData, meta.sector);
      final allocation = computeAssetAllocation(priceData, meta.assetClass);

      final returns = computeDailyReturns(priceData);
      final expReturns = computeExpectedReturns(returns);
      final covMatrix = computeCovariance(returns);

      // Compute Gainers/Losers
      final cumulativeReturns = <String, double>{};
      returns.forEach((asset, rList) {
        double cumulative = 1.0;
        for (var r in rList) cumulative *= (1 + r);
        cumulativeReturns[asset] = cumulative - 1;
      });
      final sorted = cumulativeReturns.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));
      topGainers = sorted.take(5).toList();
      topLosers = sorted.reversed.take(5).toList();

      final optWeights = optimizePortfolio(expReturns, covMatrix);

      // Efficient Frontier
      final List<FlSpot> frontier = [];
      final assets = expReturns.keys.toList();
      for (int i = 0; i < 100; i++) {
        final w = randomWeights(assets.length);
        double ret = 0, variance = 0;
        for (int j = 0; j < assets.length; j++) {
          ret += w[j] * expReturns[assets[j]]!;
          for (int k = 0; k < assets.length; k++) {
            variance += w[j] * w[k] * covMatrix[assets[j]]![assets[k]]!;
          }
        }
        frontier.add(FlSpot(sqrt(variance), ret));
      }

      // My Portfolio (equal weights baseline)
      if (assets.isNotEmpty) {
        final w = List.filled(assets.length, 1 / assets.length);
        double portReturn = 0, portVar = 0;
        for (int j = 0; j < assets.length; j++) {
          portReturn += w[j] * expReturns[assets[j]]!;
          for (int k = 0; k < assets.length; k++) {
            portVar += w[j] * w[k] * covMatrix[assets[j]]![assets[k]]!;
          }
        }
        myPortfolioPoint = FlSpot(sqrt(portVar), portReturn);
      }

      setState(() {
        portfolioValue = totalValue;
        sectorExposure = sector;
        assetAllocation = allocation;
        optimalWeights = optWeights;
        efficientFrontier = frontier;
        hasData = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(title: Text("Portfolio Analytics"), backgroundColor: Colors.orange),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _glowingValueCard(),
              SizedBox(height: 16),
              ElevatedButton.icon(
                icon: Icon(Icons.upload_file),
                label: Text("Upload Holdings CSV"),
                onPressed: pickAndLoadCSV,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.orange,
                  foregroundColor: Colors.white,
                  shape: StadiumBorder(),
                ),
              ),
              SizedBox(height: 20),

              if (hasData) ...[
                _animatedTopMovers(),

                SizedBox(height: 20),
                Text("Asset Allocation", style: Theme.of(context).textTheme.titleMedium),
                SizedBox(height: 200, child: _animatedPieChart()),

                SizedBox(height: 20),
                Text("Sector Exposure", style: Theme.of(context).textTheme.titleMedium),
                SizedBox(height: 200, child: _animatedTreemap()),

                SizedBox(height: 20),
                Text("Risk/Return Nebula", style: Theme.of(context).textTheme.titleMedium),
                SizedBox(height: 250, child: _animatedRiskReturnChart()),

                SizedBox(height: 20),
                Text("Rebalance Suggestions", style: Theme.of(context).textTheme.titleMedium),
                _animatedRebalanceCards(),
              ],
            ],
          ),
        ),
      ),
    );
  }

  // -------- Animated UI Widgets --------
  Widget _glowingValueCard() {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.8, end: 1.2),
      duration: Duration(seconds: 2),
      curve: Curves.easeInOut,
      builder: (context, value, _) {
        return Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Colors.orange.withOpacity(0.4),
                blurRadius: 30 * value,
                spreadRadius: 5 * value,
              )
            ],
          ),
          child: Card(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Center(
                child: Text(
                  hasData ? "₹${portfolioValue.toStringAsFixed(0)}" : "Upload your CSV to see portfolio value",
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.orange.shade700),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _animatedTopMovers() {
    return AnimatedOpacity(
      opacity: 1,
      duration: Duration(milliseconds: 800),
      child: _topMoversTables(),
    );
  }

  Widget _animatedPieChart() {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: 1200),
      builder: (context, value, _) {
        return PieChart(
          PieChartData(
            sections: assetAllocation.entries.map((entry) {
              final color = Colors.primaries[assetAllocation.keys.toList().indexOf(entry.key) % Colors.primaries.length];
              return PieChartSectionData(
                value: entry.value * value,
                title: "${entry.key} ${(entry.value * 100 * value).toStringAsFixed(1)}%",
                color: color,
              );
            }).toList(),
          ),
        );
      },
    );
  }

  Widget _animatedTreemap() {
    final tiles = sectorExposure.entries.map((entry) {
      final color = Colors.primaries[entry.key.hashCode % Colors.primaries.length];
      return TreemapTile(
        entry.value,
        child: AnimatedContainer(
          duration: Duration(milliseconds: 800),
          decoration: BoxDecoration(
            color: color.withOpacity(0.8),
            borderRadius: BorderRadius.circular(12),
            boxShadow: [BoxShadow(color: color.withOpacity(0.4), blurRadius: 12, spreadRadius: -2)],
          ),
          child: Center(
            child: Text(
              "${entry.key}\n${(entry.value * 100).toStringAsFixed(1)}%",
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }).toList();

    return Treemap(data: tiles, padding: 4, spacing: 4);
  }

  Widget _animatedRiskReturnChart() {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: 1500),
      builder: (context, value, _) {
        final cutoff = (efficientFrontier.length * value).floor().clamp(1, efficientFrontier.length);
        final partialFrontier = efficientFrontier.take(cutoff).toList();
        return LineChart(
          LineChartData(
            lineBarsData: [
              LineChartBarData(
                spots: partialFrontier,
                isCurved: true,
                colors: [Colors.blueAccent],
                barWidth: 3,
                dotData: FlDotData(show: false),
                belowBarData: BarAreaData(
                  show: true,
                  gradient: LinearGradient(
                    colors: [Colors.blueAccent.withOpacity(0.2), Colors.transparent],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                  ),
                ),
              ),
              if (myPortfolioPoint != null)
                LineChartBarData(
                  spots: [myPortfolioPoint!],
                  isCurved: false,
                  colors: [Colors.redAccent],
                  dotData: FlDotData(show: true),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _animatedRebalanceCards() {
    return Column(
      children: optimalWeights.entries.toList().asMap().entries.map((entry) {
        final index = entry.key;
        final e = entry.value;
        return TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: 1),
          duration: Duration(milliseconds: 600),
          curve: Curves.easeOut,
          delay: Duration(milliseconds: index * 200),
          builder: (context, value, _) {
            return Opacity(
              opacity: value,
              child: Transform.translate(
                offset: Offset(0, 20 * (1 - value)),
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(color: Colors.blueAccent.withOpacity(0.3), blurRadius: 15, spreadRadius: -2),
                    ],
                  ),
                  child: Card(
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    child: ListTile(
                      title: Text(e.key),
                      trailing: Text("${(e.value * 100).toStringAsFixed(1)}%"),
                    ),
                  ),
                ),
              ),
            );
          },
        );
      }).toList(),
    );
  }

  // -------- Non-animated base tables --------
  Widget _topMoversTables() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Card(
            child: Column(
              children: [
                Container(color: Colors.green.shade100, padding: EdgeInsets.all(8), child: Center(child: Text("Top 5 Gainers", style: TextStyle(fontWeight: FontWeight.bold)))),
                ...topGainers.map((e) => ListTile(title: Text(e.key), trailing: Text("+${(e.value * 100).toStringAsFixed(1)}%", style: TextStyle(color: Colors.green)))),
              ],
            ),
          ),
        ),
        SizedBox(width: 8),
        Expanded(
          child: Card(
            child: Column(
              children: [
                Container(color: Colors.red.shade100, padding: EdgeInsets.all(8), child: Center(child: Text("Top 5 Losers", style: TextStyle(fontWeight: FontWeight.bold)))),
                ...topLosers.map((e) => ListTile(title: Text(e.key), trailing: Text("${(e.value * 100).toStringAsFixed(1)}%", style: TextStyle(color: Colors.red)))),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
