// One address for the site: www.prodline.build and the workers.dev address redirect to prodline.build.
const HOME = "prodline.build";

export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    if (url.hostname !== HOME && url.hostname !== "localhost" && url.hostname !== "127.0.0.1") {
      url.protocol = "https:";
      url.hostname = HOME;
      url.port = "";
      return Response.redirect(url.toString(), 301);
    }
    return env.ASSETS.fetch(request);
  },
};
