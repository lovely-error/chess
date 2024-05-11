
// ignore_for_file: unnecessary_this

import 'dart:convert';
import 'dart:math';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_svg/flutter_svg.dart' as svg;
import 'package:web_socket_channel/web_socket_channel.dart';


class ChessFigurePictures with ChangeNotifier {
  ChessFigurePictures() {
    for (final figure in ChessPieceType.values) {
      final figureName = figure.name;
      if (figureName == "none") continue;
      svg.vg.loadPicture(svg.SvgAssetLoader("media/$figureName.svg"), null).then((value) {
        this._figurePictures[figure] = value;
        this.notifyListeners();
      });
    }
  }
  final Map<ChessPieceType, svg.PictureInfo?> _figurePictures = {};
}
late ChessFigurePictures _chessFiguresPictures;

sealed class ClientServerMsgTypes {
  static const int gameSessionStart = 0;
  static const int positionUpdate = 1;
}

void main() async {

  final binding = WidgetsFlutterBinding.ensureInitialized();

  final implicitView = binding.platformDispatcher.implicitView!;
  final rootView = View(view: implicitView, child: const ApplicationRoot());

  binding.attachRootWidget(rootView);

  _chessFiguresPictures = ChessFigurePictures();
}


class ApplicationRoot extends StatefulWidget {
  const ApplicationRoot({super.key});
  @override
  State<StatefulWidget> createState() {
    return ApplicationRootState();
  }
}

enum ConnectionState {
  intro,
  askedServerToInitiateSession,
  sessionInitiated
}
class ApplicationRootSharedState with ChangeNotifier {

  ApplicationRootSharedState();

  ConnectionState _connectionState = ConnectionState.intro;

  void askSessionInit() {
    this._connectionState = ConnectionState.askedServerToInitiateSession;
    this.notifyListeners();
  }
}
class ApplicationRootState extends State<ApplicationRoot> {

  late ApplicationRootSharedState _sharedState;
  late ChessBoardController _chessBoardController;
  late WebSocketChannel _serverWebSocketChannel;
  set _mineTurn(bool newVal) => _chessBoardController.isYourTurn = newVal;
  bool get _mineTurn => _chessBoardController.isYourTurn;
  final Color _mineColor = Colors.amber;
  final Color _opponentColor = Colors.deepOrange;

  @override
  void initState() {
    super.initState();
    this._sharedState = ApplicationRootSharedState();
    this._chessBoardController = ChessBoardController(
      mineColor: _mineColor,
      opponentColor: _opponentColor
    );
    this._serverWebSocketChannel = WebSocketChannel.connect(Uri.parse("ws://vessel:19191"));
    this._serverWebSocketChannel.stream.listen(_positionReciever);
    this._chessBoardController.subscribeToPiecePositionChanges(_positionSender);
  }

  @override
  void dispose() async {
    this._chessBoardController.unsubscribeFromPiecePositionChanges(_positionSender);
    super.dispose();
  }
  void _positionReciever(dynamic event) {
    final object = jsonDecode(event);
    switch (object["type"]) {
      case ClientServerMsgTypes.gameSessionStart:
        setState(() {
          this._mineTurn = object["starts_first"];
          this._sharedState._connectionState = ConnectionState.sessionInitiated;
        });
        break;
      case ClientServerMsgTypes.positionUpdate:
        this._mineTurn = true;
        final srcRow = 7 - object["srcRow"];
        final srcCol = object["srcCol"];
        final oldPos = ChessboardCoordinate(srcRow.toInt(), srcCol);
        final dstRow = 7 - object["dstRow"];
        final dstCol = object["dstCol"];
        final newPos = ChessboardCoordinate(dstRow.toInt(), dstCol);
        this._chessBoardController._movePieceByCoordinatesUnconditionally(oldPos, newPos);
        setState(() {});
        break;
      default:
        break;
    }
  }
  void _positionSender(ChessPiece p0, ChessPiece p1) {
    final srcRow = p0.row;
    final srcCol = p0.column;
    final dstRow = p1.row;
    final dstCol = p1.column;
    final msg = jsonEncode({
      "type" : ClientServerMsgTypes.positionUpdate,
      "srcRow" : srcRow,
      "srcCol" : srcCol,
      "dstRow" : dstRow,
      "dstCol" : dstCol,
    });
    this._serverWebSocketChannel.sink.add(msg);
    setState(() {}); // update turn plate
  }

  Widget getBody() {
    switch (this._sharedState._connectionState) {
      case ConnectionState.intro:
        return IntroView(sharedState: this._sharedState,);
      case ConnectionState.askedServerToInitiateSession:
        return const WaitScreen();
      case ConnectionState.sessionInitiated:
        return Column(
          children: [
            Container(
              height: 500,
              width: 500,
              alignment: Alignment.center,
              child: ChessBoard(chessBoardController: this._chessBoardController)
            ),
            _turn,
          ],
        );
    }
  }
  Widget get _turn =>
    _mineTurn
    ? Text(
      "It's your turn",
      style: TextStyle(
        fontSize: 15,
        fontWeight: FontWeight.bold,
        color: _mineColor
      ),
    )
    : Text(
      "It's your opponents turn",
      style: TextStyle(
        fontSize: 15,
        fontWeight: FontWeight.bold,
        color: _opponentColor
      ),
    );

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.ltr,
      child: ListenableBuilder(
        listenable: this._sharedState,
        builder: (context, child) => Stack(
          alignment: Alignment.topLeft,
          fit: StackFit.expand,
          children: [
            const ColoredBox(color: Colors.deepPurple),
            getBody(),
          ],
        ),
      ),
    );
  }
}

class WaitScreen extends StatelessWidget {
  const WaitScreen({super.key});
  @override
  Widget build(BuildContext context) {
    const numPlayers = "???";
    return Column(
      children: [
        Expanded(
          child: Container(
            alignment: Alignment.center,
            child: const Text(
              "Waiting for some opponent to connect...",
              style: TextStyle(
                fontSize: 25,
                fontWeight: FontWeight.bold,
                color: Colors.amber
              ),
            ),
          ),
        ),
        // loading pbar
        const Text(
          "Currently $numPlayers online",
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: Colors.lightGreen
          ),
        )
      ],
    );
  }
}

class IntroView extends StatelessWidget {
  const IntroView({
    super.key,
    required ApplicationRootSharedState sharedState
  }) : _sharedState = sharedState;

  final ApplicationRootSharedState _sharedState;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Text(
          "Mately checks!",
          textDirection: TextDirection.ltr,
          style: TextStyle(
            fontSize: 30,
            fontWeight: FontWeight.w900,
            fontStyle: FontStyle.italic,
            color: Colors.green
          ),
        ),
        const SizedBox(height: 20,),
        OutlinedButton(
          onPressed: () {
            this._sharedState.askSessionInit();
          },
          child: const Text("Play"),
        ),
      ],
    );
  }
}

enum ChessPieceType {
  pawn,
  rook, knight, bishop, king, queen,
  none
}
enum ChessPieceCamp {
  opponent, me, neither
}
class ChessPiece {
  ChessPiece(this.type, this.row, this.column, this.chessPieceCamp);
  ChessPieceType type;
  int row;
  int column;
  ChessPieceCamp chessPieceCamp;

  @override
  String toString() {
    var strRepr = "";
    strRepr += this.chessPieceCamp.name;
    strRepr += " ";
    strRepr += this.type.name;
    strRepr += " @ row:";
    strRepr += this.row.toString();
    strRepr += " column:";
    strRepr += this.column.toString();
    return strRepr;
  }
}

class ChessboardCoordinate {
  ChessboardCoordinate(this.row, this.column);
  int row;
  int column;
}

class ChessBoardController {
  ChessBoardController({
    this.isYourTurn = true,
    this.opponentColor = Colors.red,
    this.mineColor = Colors.green
  });

  final Color opponentColor;
  final Color mineColor;
  late final List<List<ChessPiece>> _pieces = _initialArrangement();
  late ChessBoardView _view;
  bool isYourTurn;
  final List<void Function(ChessPiece, ChessPiece)> _listeners = [];
  bool isGameOver = false;


  void subscribeToPiecePositionChanges(void Function(ChessPiece, ChessPiece) operation) {
    this._listeners.add(operation);
  }
  void unsubscribeFromPiecePositionChanges(void Function(ChessPiece, ChessPiece) operation) {
    this._listeners.remove(operation);
  }
  void _movePieceByCoordinatesUnconditionally(ChessboardCoordinate oldPos, ChessboardCoordinate newPos) {
    final old = this._pieces[oldPos.row][oldPos.column];
    final new_ = this._pieces[newPos.row][newPos.column];
    this._moveUnconditionally(old, new_);
  }
  void _movePieceByCoordinates(ChessboardCoordinate oldPos, ChessboardCoordinate newPos) {
    final src = this._pieces[oldPos.row][oldPos.column];
    final dst = this._pieces[newPos.row][newPos.column];
    final allowedMove = _checkMoveValidity(src, dst);
    if (allowedMove) {
      if (dst.type == ChessPieceType.king) {
        this.isGameOver = true;
      }
      for (final listener in this._listeners) {
        listener(src, dst);
      }
      this.isYourTurn = !this.isYourTurn;
      this._moveUnconditionally(src, dst);
    }
    this._view._pieces.invalidate();
    this._view.markNeedsPaint();
  }
  bool _checkMoveValidity(
    ChessPiece src, ChessPiece dst
  ) {
    if (this.isGameOver) { return false; }
    var allowedMove = true;
    allowedMove &=
      (this._pieces[dst.row][dst.column].type == ChessPieceType.none) ||
      (this._pieces[dst.row][dst.column].chessPieceCamp == ChessPieceCamp.opponent);
    allowedMove &= this.isYourTurn;
    if (allowedMove) {
      allowedMove = false;
      switch (src.type) {
        case ChessPieceType.pawn:
          allowedMove |=
            src.column == dst.column &&
            (src.row - 1 == dst.row || src.row - 2 == dst.row);
          final spread = (src.column - dst.column).abs();
          final reach = (src.row - dst.row).abs();
          allowedMove |=
            (spread == 1) && (reach == 1) && (dst.type != ChessPieceType.none);
          break;
        case ChessPieceType.rook:
          if (src.column == dst.column) {
            // vertical move
            var src_ = src.row;
            var dst_ = dst.row;
            if (src_ > dst_) {
              final tmp = src_;
              src_ = dst_;
              dst_ = tmp;
            }
            allowedMove |= this._pieces
              .getRange(src_ + 1, dst_)
              .map((e) => e[src.column].type == ChessPieceType.none)
              .fold(true, (acc, e) => acc && e);
          } else if (src.row == dst.row) {
            // horizontal move
            var src_ = src.column;
            var dst_ = dst.column;
            if (src_ > dst_) {
              final tmp = src_;
              src_ = dst_;
              dst_ = tmp;
            }
            allowedMove |= this._pieces[src.row]
              .getRange(src_ + 1, dst_)
              .map((e) => e.type == ChessPieceType.none)
              .fold(true, (acc, e) => acc && e);
          }
          break;
        case ChessPieceType.knight:
          allowedMove |=
            (((src.row - dst.row).abs() == 2) &&
            ((src.column - dst.column).abs() == 1)) ||
            (((src.row - dst.row).abs() == 1) &&
            ((src.column - dst.column).abs() == 2)) ;
          break;
        case ChessPieceType.bishop:
          final vDistance = (src.row - dst.row).abs();
          final hDistance = (src.column - dst.column).abs();
          allowedMove |= vDistance == hDistance;
          if (allowedMove) {
            var rowOne = 1;
            if (src.row > dst.row) {
              rowOne *= -1;
            }
            final startRow = src.row + rowOne;
            final endRow = dst.row;
            var indexRow = startRow;
            var columnOne = 1;
            if (src.column > dst.column) {
              columnOne *= -1;
            }
            final startColumn = src.column;
            var indexColumn = startColumn + columnOne;
            while (indexRow != endRow) {
              allowedMove &= this._pieces[indexRow][indexColumn].type == ChessPieceType.none;
              if (!allowedMove) break;
              indexRow += rowOne;
              indexColumn += columnOne;
            }
          }
          break;
        case ChessPieceType.king:
          final hDistance = (src.row - dst.row).abs();
          final vDistance = (src.column - dst.column).abs();
          final hypot = sqrt((hDistance * hDistance) + (vDistance * vDistance)).floor();
          allowedMove |= hypot == 1;
          break;
        case ChessPieceType.queen:
          final hDistance = (src.row - dst.row).abs();
          final vDistance = (src.column - dst.column).abs();
          final hypot = sqrt((hDistance * hDistance) + (vDistance * vDistance)).floor();
          allowedMove |= hypot == 1;
          if (!allowedMove) {
            allowedMove |= vDistance == hDistance;
            if (allowedMove) {
              var rowOne = 1;
              if (src.row > dst.row) {
                rowOne *= -1;
              }
              final startRow = src.row + rowOne;
              final endRow = dst.row;
              var indexRow = startRow;
              var columnOne = 1;
              if (src.column > dst.column) {
                columnOne *= -1;
              }
              final startColumn = src.column;
              var indexColumn = startColumn + columnOne;
              while (indexRow != endRow) {
                allowedMove &= this._pieces[indexRow][indexColumn].type == ChessPieceType.none;
                if (!allowedMove) break;
                indexRow += rowOne;
                indexColumn += columnOne;
              }
            }
          }
          if (!allowedMove) {
            if (src.column == dst.column) {
              // vertical move
              var src_ = src.row;
              var dst_ = dst.row;
              if (src_ > dst_) {
                final tmp = src_;
                src_ = dst_;
                dst_ = tmp;
              }
              allowedMove |= this._pieces
                .getRange(src_ + 1, dst_)
                .map((e) => e[src.column].type == ChessPieceType.none)
                .fold(true, (acc, e) => acc && e);
            } else if (src.row == dst.row) {
              // horizontal move
              var src_ = src.column;
              var dst_ = dst.column;
              if (src_ > dst_) {
                final tmp = src_;
                src_ = dst_;
                dst_ = tmp;
              }
              allowedMove |= this._pieces[src.row]
                .getRange(src_ + 1, dst_)
                .map((e) => e.type == ChessPieceType.none)
                .fold(true, (acc, e) => acc && e);
            }
          }
          break;
        case ChessPieceType.none:
          return false;
      }
    }
    return allowedMove;
  }
  void _moveUnconditionally(ChessPiece src, ChessPiece dst) {
    final cdst = this._pieces[dst.row][dst.column];
    cdst.type = src.type;
    cdst.chessPieceCamp = src.chessPieceCamp;
    final csrc = this._pieces[src.row][src.column];
    csrc.type = ChessPieceType.none ;
    csrc.chessPieceCamp = ChessPieceCamp.neither;
  }
  List<ChessPiece> _row(ChessPieceCamp camp) {
    var row = 0;
    if (camp == ChessPieceCamp.me) {
      row = 7;
    }
    return [
      ChessPiece(ChessPieceType.rook, row, 0, camp),
      ChessPiece(ChessPieceType.knight, row, 1, camp),
      ChessPiece(ChessPieceType.bishop, row, 2, camp),
      ChessPiece(ChessPieceType.king, row, 3, camp),
      ChessPiece(ChessPieceType.queen, row, 4, camp),
      ChessPiece(ChessPieceType.bishop, row, 5, camp),
      ChessPiece(ChessPieceType.knight, row, 6, camp),
      ChessPiece(ChessPieceType.rook, row, 7, camp),
    ];
  }
  List<List<ChessPiece>> _initialArrangement() {
    var items = [
      _row(ChessPieceCamp.opponent),
      List.generate(8, (column) {
        return ChessPiece(ChessPieceType.pawn, 1, column, ChessPieceCamp.opponent);
      },),
      ...List.generate(4, (row) => List.generate(8, (column) =>
        ChessPiece(ChessPieceType.none, row + 2, column, ChessPieceCamp.neither))),
      List.generate(8, (column) {
        return ChessPiece(ChessPieceType.pawn, 6, column, ChessPieceCamp.me);
      },),
      _row(ChessPieceCamp.me)
    ];
    return items;
  }
}

class Memoised<T> {
  Memoised(this.constructor);
  T? value;
  T Function() constructor;

  void invalidate() {
    this.value = null;
  }
  T get() {
    if (value == null) { this.value = this.constructor(); }
    return this.value!;
  }
  set(T newItem) {
    this.value = newItem;
  }
}

class ChessBoard extends LeafRenderObjectWidget {
  const ChessBoard({super.key, required this.chessBoardController});

  final ChessBoardController chessBoardController;

  @override
  RenderObject createRenderObject(BuildContext context) {
    final view = ChessBoardView(WeakReference(chessBoardController));
    this.chessBoardController._view = view;
    return view;
  }
}

class ChessBoardView extends RenderBox {

  ChessBoardView(this._chessBoardController) {
    _boardBackground = Memoised(_drawBoardBackground);
    _pieces = Memoised(_drawPieces);
    _chessFiguresPictures.addListener(() {
      this._pieces.invalidate();
      this.markNeedsPaint();
    });
  }

  final WeakReference<ChessBoardController> _chessBoardController;
  double get cellSize => this.size.width / 8;
  late Memoised<Picture> _boardBackground;
  late Memoised<Picture> _pieces;
  ChessPiece? _pieceInDrag;
  Offset _dragOffset = Offset.zero;
  late final Map<ChessPieceCamp, Color> _figureColorRemap = {
    ChessPieceCamp.opponent : this._chessBoardController.target!.opponentColor,
    ChessPieceCamp.me : this._chessBoardController.target!.mineColor
  };
  final List<Color> _boardColors = [
    Colors.white,
    Colors.black38
  ];


  Picture _drawPieces() {
    final rec = PictureRecorder();
    final canvas = Canvas(rec);
    var text = TextPainter(textDirection: TextDirection.ltr);
    const textStyle = TextStyle(color: Colors.red, fontSize: 10);
    for (final row in _chessBoardController.target!._pieces) {
      for (final figure in row) {
        if (figure.type == ChessPieceType.none) { continue; }
        if (this._pieceInDrag != null) {
          var skipThisCusInDrag = this._pieceInDrag!.row == figure.row;
          skipThisCusInDrag &= this._pieceInDrag!.column == figure.column;
          if (skipThisCusInDrag) continue;
        }
        // inverted cus of bug??
        var cornerX = figure.column * this.cellSize;
        var cornerY = figure.row * this.cellSize;
        final figurePicture = _chessFiguresPictures._figurePictures[figure.type];
        if (figurePicture != null) {
          final fs = figurePicture.size;
          cornerX += (this.cellSize - fs.height) / 2;
          cornerY += (this.cellSize - fs.width) / 2;
          canvas.save();
          canvas.translate(cornerX, cornerY);
          canvas.saveLayer(
            Offset.zero & this.size,
            Paint()..blendMode=BlendMode.srcOver);
          final paint = Paint()..color=this._figureColorRemap[figure.chessPieceCamp]!;
          canvas.drawPaint(paint);
          canvas.saveLayer(
            Offset.zero & this.size,
            Paint()..blendMode=BlendMode.dstATop);
          canvas.drawPicture(figurePicture.picture);
          canvas.restore();
          canvas.restore();
          canvas.restore();
        } else {
          text.text = TextSpan(text: figure.type.name, style: textStyle);
          text.layout(maxWidth: this.cellSize);
          text.paint(canvas, Offset(cornerX, cornerY));
        }
      }
    }
    return rec.endRecording();
  }
  Picture _drawBoardBackground() {
    final rec = PictureRecorder();
    final canvas = Canvas(rec);
    var paint = Paint();
    var x = 0;
    var y = 0;
    while (x != 8) {
      y = 0;
      while (y != 8) {
        if (y.isEven ^ x.isEven) {
          paint.color=this._boardColors[0];
        } else {
          paint.color=this._boardColors[1];
        }
        canvas.drawRect(
          Offset(x * this.cellSize, y * this.cellSize) &
          Size(this.cellSize, this.cellSize),
          paint);
        y += 1;
      }
      x += 1;
    }
    return rec.endRecording();
  }

  @override
  bool hitTestSelf(Offset position) {
    return true;
  }
  @override
  void handleEvent(PointerEvent event, covariant BoxHitTestEntry entry) {
    switch (event) {
      case PointerDownEvent pde:
        final row = (pde.localPosition.dy / this.cellSize).floor();
        final column = (pde.localPosition.dx / this.cellSize).floor();
        final touchedFigure = this._chessBoardController.target!._pieces[row][column];
        if (touchedFigure.type == ChessPieceType.none) return;
        if (touchedFigure.chessPieceCamp == ChessPieceCamp.opponent) return;
        this._pieceInDrag = touchedFigure;
        this._pieces.invalidate();
        return;
      case PointerMoveEvent pme:
        final offset = Offset(pme.localPosition.dx, pme.localPosition.dy);
        this._dragOffset = offset;
        this.markNeedsPaint();
        return;
      case PointerUpEvent pue:
        final dstRow = (pue.localPosition.dy / this.cellSize).floor();
        final dstColumn = (pue.localPosition.dx / this.cellSize).floor();
        if (this._pieceInDrag == null) { return; }
        final endedInSamePlace =
          this._pieceInDrag!.row == dstRow && this._pieceInDrag!.column == dstColumn;
        final endedBeyoundTheBoardBondry =
          (pue.localPosition.dx < 0 || pue.localPosition.dx > this.size.width) ||
          (pue.localPosition.dy < 0 || pue.localPosition.dy > this.size.height);
        if (endedInSamePlace || endedBeyoundTheBoardBondry) {
          this._pieceInDrag = null;
          this._pieces.invalidate();
          markNeedsPaint();
          return;
        }
        final srcRow = this._pieceInDrag!.row;
        final srcColumn = this._pieceInDrag!.column;
        this._chessBoardController.target!._movePieceByCoordinates(
          ChessboardCoordinate(srcRow, srcColumn),
          ChessboardCoordinate(dstRow, dstColumn)
        );
        this._pieceInDrag = null;
    }
  }
  @override
  bool get sizedByParent => true;
  @override
  Size computeDryLayout(covariant BoxConstraints constraints) {
    final dims = constraints.normalize();
    final edgeSize = min(dims.maxHeight, dims.maxWidth);
    return Size(edgeSize, edgeSize);
  }
  @override
  void performResize() {
    final dims = this.constraints.normalize();
    final edgeSize = min(dims.maxHeight, dims.maxWidth);
    _boardBackground.invalidate();
    _pieces.invalidate();
    this.size = Size(edgeSize, edgeSize);
  }
  @override
  void paint(PaintingContext context, Offset offset) {
    final canvas = context.canvas;
    canvas.save();
    canvas.translate(offset.dx, offset.dy);

    canvas.drawPicture(_boardBackground.get());
    canvas.drawPicture(_pieces.get());

    if (this._pieceInDrag != null && this._pieceInDrag!.type != ChessPieceType.none) {
      final piece = this._pieceInDrag!;
      final img = _chessFiguresPictures._figurePictures[piece.type];
      if (img != null) {
        canvas.save();
        canvas.translate(
          this._dragOffset.dx - (this.cellSize / 3),
          this._dragOffset.dy - (this.cellSize / 3));
        canvas.saveLayer(
          Offset.zero & this.size,
          Paint()..blendMode=BlendMode.srcOver);
        final paint = Paint()..color=this._figureColorRemap[piece.chessPieceCamp]!;
        canvas.drawPaint(paint);
        canvas.saveLayer(
          Offset.zero & this.size,
          Paint()..blendMode=BlendMode.dstATop);
        canvas.drawPicture(img.picture);
        canvas.restore();
      }
    }

    canvas.restore();
  }
}