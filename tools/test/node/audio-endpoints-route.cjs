'use strict';
// The suites' route for /audio/endpoints (CL-044-08): the audio selects offer only listed
// endpoints; the fixture endpoints, the entries the caller passes, are listed by this route (no
// audio device is read for them), in place of the station's own listing.
async function routeAudioEndpoints(context, inputs, outputs) {
  await context.route('**/audio/endpoints', async route => {
    // A station stopped with its window open (mid-test or at teardown) refuses, as it really would.
    try {
      const origin = new URL(route.request().url()).origin, profile = await (await route.fetch({url: origin + '/profile', method: 'GET'})).json();
      await route.fulfill({json: {v: 1, profile_id: profile.profile_id, boot_id: profile.boot_id, inputs, outputs}});
    } catch {await route.abort('connectionrefused').catch(() => {});}
  });
}

module.exports = {routeAudioEndpoints};
