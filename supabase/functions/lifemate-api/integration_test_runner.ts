const files = Deno.args;
if (files.length === 0) {
  console.error("No integration test files were provided.");
  Deno.exit(2);
}

const failures: string[] = [];
for (const file of files) {
  console.log(`\n=== integration: ${file} ===`);
  const command = new Deno.Command(Deno.execPath(), {
    args: [
      "test",
      "--no-check",
      "--allow-env",
      "--allow-net=localhost:5432,127.0.0.1:5432",
      file,
    ],
    stdin: "null",
    stdout: "inherit",
    stderr: "inherit",
  });
  const result = await command.output();
  if (!result.success) failures.push(file);
}

if (failures.length > 0) {
  console.error(
    `\nIntegration failures (${failures.length}): ${failures.join(", ")}`,
  );
  Deno.exit(1);
}
