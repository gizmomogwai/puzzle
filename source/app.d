import std.stdio;
import std.string;
import std.random;
import std.math : abs;
import imageformats;
import std.conv;
void swapCols(IFImage* image, int colA, int colB) {
  writeln("swapping ", colA, " and ", colB);
  for (int j=0; j<image.h; ++j) {
    int p1Idx = (j * image.w + colA) * 3;
    int p2Idx = (j * image.w + colB) * 3;

    ubyte b1 = image.pixels[p1Idx];
    ubyte b2 = image.pixels[p1Idx+1];
    ubyte b3 = image.pixels[p1Idx+3];

    image.pixels[p1Idx] = image.pixels[p2Idx];
    image.pixels[p1Idx+1] = image.pixels[p2Idx+1];
    image.pixels[p1Idx+2] = image.pixels[p2Idx+2];

    image.pixels[p2Idx] = b1;
    image.pixels[p2Idx+1] = b2;
    image.pixels[p2Idx+2] = b3;
  }
}

int calcDelta(IFImage* image, int colA, int colB) {
  int colAStart = colA * 3;
  int colBStart = colB * 3;
  int sum = 0;
  for (int y=0; y<image.h; y++) {
    int offset = y*image.w * 3;

    sum += abs(image.pixels[offset + colAStart] - image.pixels[offset + colBStart]);
    sum += abs(image.pixels[offset + colAStart + 1] - image.pixels[offset + colBStart + 1]);
    sum += abs(image.pixels[offset + colAStart + 2] - image.pixels[offset + colBStart + 2]);
  }
  return sum;
}

struct Match {
  int column;
  int index;
  int delta;
}

Match findBest(int forColumn, IFImage* image, ref int[] todo) {
  int delta = int.max;
  int column = -1;
  int index = -1;

  int i = 0;
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

int[] remove(int[] data, int idx) {
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

void copyColumn(IFImage* from, int sourceIndex, IFImage* to, int targetIndex) {
  for (int j=0; j<from.h; j++) {
    int sourceOffset = (j*from.w + sourceIndex) * from.c;
    int targetOffset = (j*from.w + targetIndex) * from.c;
    to.pixels[targetOffset] = from.pixels[sourceOffset];
    to.pixels[targetOffset+1] = from.pixels[sourceOffset+1];
    to.pixels[targetOffset+2] = from.pixels[sourceOffset+2];
  }
}

IFImage* reassembleWith(IFImage image, int[] order) {
  auto pixels = new ubyte[image.pixels.length];
  auto res = new IFImage(image.w, image.h, image.c, pixels);
  int targetIndex = 0;
  foreach (sourceIndex; order) {
    copyColumn(&image, sourceIndex, res, targetIndex);
    targetIndex++;
  }
  return res;
}

IFImage* unscramble(IFImage image) {
  auto todo = new int[image.w-1];
  for (int i=1; i<image.w; i++) {
    todo[i-1] = i;
  }

  int[] result;
  result ~= 0;

  while (todo.length > 0) {
    writeln("todo: ", todo.length);
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
  writeln("result: ", result);
  return image.reassembleWith(result);
}

unittest {
  const w = 2;
  const h = 2;
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


int main(string[] args) {
  writeln(args);
  if (args.length != 3) {
    writeln("Usage: %s scramble|unscramble input (outputname is derived from inputname)".format(args[0]));
    return 1;
  }
  auto action = args[1];
  auto inputFileName = args[2];
  auto outputFileName = "%s.%sd.png".format(inputFileName, action);
  auto input = read_image(inputFileName, ColFmt.RGB);

  if (action == "scramble") {
    writeln(input.w, "x", input.h, "x", input.c);
    for (int i=0; i<input.w-1; ++i) {
      int colA = i;
      int colB = uniform(colA, input.w);

      swapCols(&input, colA, colB);
    }
    write_png(outputFileName, input.w, input.h, input.pixels);

    auto output = input.unscramble();
    write_png("test.png", output.w, output.h, output.pixels);
  } else if (action == "unscramble") {
    write_png(outputFileName, input.w, input.h, input.pixels);

    writeln("nyi");
    return 1;
  }
  return 0;
}