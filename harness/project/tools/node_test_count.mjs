// A node --test reporter for filter_run.py: one line per test that ran (passed or failed),
// written to its destination file. Suites, skipped and todo tests are not counted, nor the
// stand-in test that node reports for a file in which no test ran (its name is the file's).
export default async function* count(source) {
  for await (const event of source) {
    if (event.type !== 'test:pass' && event.type !== 'test:fail') continue;
    const data = event.data;
    if (!data.details || data.details.type !== 'test' || data.skip || data.todo) continue;
    if (data.nesting === 0 && data.name === data.file) continue;
    yield `${event.type === 'test:pass' ? 'pass' : 'fail'} ${data.name}\n`;
  }
}
