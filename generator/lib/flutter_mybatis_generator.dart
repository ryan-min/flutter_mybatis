import 'package:build/build.dart';
import 'package:source_gen/source_gen.dart';

import 'src/mapper_generator.dart';

/// Entry point referenced from `build.yaml`.
Builder mapperBuilder(BuilderOptions options) => SharedPartBuilder(
      [MapperGenerator()],
      'flutter_mybatis',
    );
