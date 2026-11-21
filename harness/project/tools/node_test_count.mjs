// A node --test reporter for filter_run.py: one line per test that ran (passed or failed),
// written to its destination file. Suites, skipped and todo tests are not counted, nor the
// stand-in test that node reports for a file in which no test ran: its name is the file's
// path as given on the command line, relative or absolute.
import path from 'node:path';

const standIn = data => data.nesting === 0 && typeof data.file === 'string'
  && path.resolve(data.name) === path.resolve(data.file);

export default async function* count(source) {
  for await (const event of source) {
    if (event.type !== 'test:pass' && event.type !== 'test:fail') continue;
    const data = event.data;
    if (!data.details || data.details.type !== 'test' || data.skip || data.todo || standIn(data)) continue;
    yield `${event.type === 'test:pass' ? 'pass' : 'fail'} ${data.name}\n`;
  }
}
