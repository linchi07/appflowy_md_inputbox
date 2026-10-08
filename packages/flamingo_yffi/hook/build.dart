import 'package:hooks/hooks.dart';
import 'package:native_toolchain_rust/native_toolchain_rust.dart';

Future<void> main(List<String> args) async {
  await build(args, (input, output) async {
    await RustBuilder(
      assetName: 'src/bindings.g.dart',
      cratePath: 'native',
      extraCargoBuildArgs: ['--locked'],
    ).run(input: input, output: output);
    output.dependencies.addAll([
      input.packageRoot.resolve('native/Cargo.toml'),
      input.packageRoot.resolve('native/Cargo.lock'),
      input.packageRoot.resolve('native/rust-toolchain.toml'),
    ]);
  });
}
