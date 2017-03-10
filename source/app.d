// see discussion https://news.ycombinator.com/item?id=12667611

import std.stdio;
import std.datetime;
import std.string;
import std.random;
import std.math;
import imageformats;
import std.conv;
import std.path;
import std.algorithm;

void swapCols(IFImage* image, int colA, int colB) {
  for (int j=0; j<image.h; ++j) {
    int p1Idx = (j * image.w + colA) * 3;
    int p2Idx = (j * image.w + colB) * 3;

    for (int i=0; i<3; ++i) {
      ubyte b = image.pixels[p1Idx + i];
      image.pixels[p1Idx + i] = image.pixels[p2Idx + i];
      image.pixels[p2Idx + i] = b;
    }
  }
}

ulong calcDelta(IFImage* image, ulong colA, ulong colB) {
  auto colAStart = colA * 3;
  auto colBStart = colB * 3;
  ulong sum = 0;
  for (ulong y=0; y<image.h; y++) {
    auto offset = y*image.w * 3;

    ulong offsetA = offset + colAStart;
    ulong offsetB = offset + colBStart;
    for (int i=0; i<3; ++i) {
      auto delta = abs(image.pixels[offsetA + i] - image.pixels[offsetB + i]);
      sum += delta;
    }
  }
  return sum;
}

unittest {
  const w = 2;
  const h = 1;
  const cf = ColFmt.RGB;
  auto i = IFImage(w, h, cf, new ubyte[w*h*cf]);
  i.pixels[0] = 0;
  i.pixels[1] = 2;
  i.pixels[2] = 0;

  i.pixels[3] = 0;
  i.pixels[4] = 0;
  i.pixels[5] = 4;

  auto d = calcDelta(&i, 0, 1);
  assert(6 == d);
}

struct Match {
  ulong column;
  ulong index;
  ulong delta;
}
import std.parallelism;

struct Work {
  IFImage* image;
  long forColumn;
  ulong[] todo;
  ulong fromIndex;
  ulong toIndex;

  ulong column = 0;
  ulong index = int.max;
  ulong delta = 0;
  Work calc() {
    delta = int.max;

    auto colAStart = forColumn * 3;
    for (auto currentIndex=fromIndex; currentIndex<toIndex; ++currentIndex) {

      auto currentColumn = todo[currentIndex];
      ulong currentDelta = 0;
      auto colBStart = currentColumn * 3;
      for (int y=0; y<image.h; y++) {
        auto offset = y*image.w * 3;

        auto offsetA = offset + colAStart;
        auto offsetB = offset + colBStart;
        for (int i=0; i<3; ++i) {
          currentDelta += abs(image.pixels[offsetA + i] - image.pixels[offsetB + i]);
        }
      }
      
      if (currentDelta < delta) {
        delta = currentDelta;
        column = currentColumn;
        index = currentIndex;
      }
    }
    return this;
  }
}

Work findBestP(ulong forColumn, IFImage* image, ref ulong[] todo) {
  Work[] work;
  for (int i=0; i<todo.length; i+=100) {
    work ~= Work(image, forColumn, todo, i, min(i+100, todo.length));
  }
  auto deltas = taskPool.map!("a.calc")(work);
  Work w;
  w.delta = int.max;
  foreach (d; deltas) {
    if (d.delta < w.delta) {
      w = d;
    }
  }
  return w;
}

unittest {
  const w = 2000;
  const h = 2000;
  const cf = ColFmt.RGB;
  auto image = IFImage(w, h, cf, new ubyte[w*h*cf]);
  writeln("test");
  Work work = Work(&image, 0, 1, 10);
  auto mt = measureTime!((TickDuration a)
                         { writeln(a.to!("msecs", float)); });
  for (int i=0; i<100; ++i) {
    auto delta = work.calc();
  }
}

unittest {
  const w = 2;
  const h = 2;
  const cf = ColFmt.RGB;
  auto image = IFImage(w, h, cf, new ubyte[w*h*cf]);
  image.pixels[0] = 0;
  image.pixels[1] = 2;
  image.pixels[2] = 0;

  image.pixels[3] = 0;
  image.pixels[4] = 0;
  image.pixels[5] = 4;

  Work work = Work(&image, 0, 1, 10);
  auto delta = work.calc();
  assert(delta.delta == 6);
  assert(delta.index == 10);
}

Match findBest(ulong forColumn, IFImage* image, ref ulong[] todo) {
  auto delta = ulong.max;
  ulong column = -1;
  ulong index = -1;

  ulong i = 0;

  foreach (c; todo) {
    auto d = calcDelta(image, forColumn, c);
    if (d < delta) {
      delta = d;
      column = c;
      index = i;
    }
    i++;
  }
  return Match(column, index, delta);
}

ulong[] remove(ulong[] data, ulong idx) {
  if (idx < 0) {
    throw new Exception("out of bounds: " ~ idx.to!string ~ " < " ~ data.length.to!string);
  }
  if (idx >= data.length) {
    throw new Exception("out of bounds: " ~ idx.to!string ~ " >= " ~ data.length.to!string);
  }
  if (data.length == 1) {
    return [];
  }
  return data[0..idx] ~ data[idx+1..$];
}

void copyColumn(IFImage* from, ulong sourceIndex, IFImage* to, ulong targetIndex) {
  for (auto j=0; j<from.h; j++) {
    auto sourceOffset = (j*from.w + sourceIndex) * from.c;
    auto targetOffset = (j*from.w + targetIndex) * from.c;
    to.pixels[targetOffset] = from.pixels[sourceOffset];
    to.pixels[targetOffset+1] = from.pixels[sourceOffset+1];
    to.pixels[targetOffset+2] = from.pixels[sourceOffset+2];
  }
}

IFImage* reassembleWith(IFImage image, ulong[] order) {
  auto pixels = new ubyte[image.pixels.length];
  auto res = new IFImage(image.w, image.h, image.c, pixels);
  ulong targetIndex = 0;
  foreach (sourceIndex; order) {
    copyColumn(&image, sourceIndex, res, targetIndex);
    targetIndex++;
  }
  return res;
}

IFImage* unscramble(IFImage image) {
  auto todo = new ulong[image.w-1];
  for (int i=1; i<image.w; i++) {
    todo[i-1] = i;
  }

  ulong[] result;
  result ~= 0;

  while (todo.length > 0) {
    writeln(todo.length);
    auto leftBest = findBest(result[0], &image, todo);
    auto rightBest = findBest(result[$-1], &image, todo);
    if (leftBest.delta < rightBest.delta) {
      result = [leftBest.column] ~ result;
      todo = remove(todo, leftBest.index);
    } else {
      result = result ~ rightBest.column;
      todo = remove(todo, rightBest.index);
    }
  }
  return image.reassembleWith(result);
}

IFImage* unscrambleP(IFImage image) {
  auto todo = new ulong[image.w-1];
  for (ulong i=1; i<image.w; i++) {
    todo[i-1] = i;
  }

  ulong[] result;
  result ~= 0;
  while (todo.length > 100) {
    writeln(todo.length);
    auto leftBest = findBestP(result[0], &image, todo);
    auto rightBest = findBestP(result[$-1], &image, todo);
    if (leftBest.delta < rightBest.delta) {
      result = [leftBest.column] ~ result;
      todo = remove(todo, leftBest.index);
    } else {
      result = result ~ rightBest.column;
      todo = remove(todo, rightBest.index);
    }
  }
  while (todo.length > 0) {
    auto leftBest = findBest(result[0], &image, todo);
    auto rightBest = findBest(result[$-1], &image, todo);
    if (leftBest.delta < rightBest.delta) {
      result = [leftBest.column] ~ result;
      todo = remove(todo, leftBest.index);
    } else {
      result = result ~ rightBest.column;
      todo = remove(todo, rightBest.index);
    }
  }
  return image.reassembleWith(result);
}

int main(string[] args) {
  writeln(args.join(" "));
  if (args.length != 3) {
    writeln("Usage: %s scramble|unscramble|unscrambleP input (outputname is derived from inputname)".format(args[0]));
    return 1;
  }
  auto action = args[1];
  auto inputFileName = args[2];
  auto outputFileName = "out/%s.%sd.png".format(baseName(inputFileName), action);
  auto input = read_image(inputFileName, ColFmt.RGB);

  if (action == "scramble") {
    writeln(input.w, "x", input.h, "x", input.c);
    for (int i=0; i<input.w-1; ++i) {
      int colA = i;
      int colB = uniform(colA, input.w);

      swapCols(&input, colA, colB);
    }
    write_png(outputFileName, input.w, input.h, input.pixels);
  } else if (action == "unscramble") {
    auto output = input.unscramble();
    write_png(outputFileName, output.w, output.h, output.pixels);
  } else if (action == "unscrambleP") {
    auto output = input.unscrambleP();
    write_png(outputFileName, output.w, output.h, output.pixels);
  }
  return 0;
}
