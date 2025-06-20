import { Loader2Icon, PlusIcon } from "lucide-react";
import { useEffect, useState } from "react";
import { toast } from "sonner";
import { ThemeProvider } from "./components/theme-provider";
import { Button } from "./components/ui/button";
import {
  Dialog,
  DialogClose,
  DialogContent,
  DialogFooter,
  DialogHeader,
  DialogTitle,
  DialogTrigger,
} from "./components/ui/dialog";
import { Input } from "./components/ui/input";
import { Toaster } from "./components/ui/sonner";

interface Feed {
  id: string;
  title: string;
  url: string;
}

interface Post {
  id: string;
  feed_id: string;
  title: string;
  post_time: string;
  thumbnail: string | null;
  description: string | null;
  content: string | null;
  url: string;
}

export default function App() {
  const [feeds, setFeeds] = useState<Record<string, Feed>>({});
  const [posts, setPosts] = useState<Post[]>([]);

  useEffect(() => {
    (async () => {
      const feeds = await fetch("/api/feeds")
        .then((res) => res.json())
        .then((feeds: Feed[]) =>
          Object.fromEntries(feeds.map((feed) => [feed.id, feed])),
        );

      setFeeds(feeds);

      const posts = await fetch("/api/posts").then((res) => res.json());

      setPosts(posts);
    })();
  }, []);

  const [open, setOpen] = useState(false);
  const [saving, setSaving] = useState(false);
  const [url, setUrl] = useState("");

  return (
    <ThemeProvider>
      <div className="max-w-4xl m-auto flex flex-col min-h-screen">
        <div className="flex mx-4 my-6">
          <h1 className="flex-1 text-2xl">Posts</h1>
          <Dialog open={open} onOpenChange={setOpen}>
            <DialogTrigger asChild>
              <Button>
                <PlusIcon /> Add
              </Button>
            </DialogTrigger>
            <DialogContent>
              <DialogHeader>
                <DialogTitle>Add feed</DialogTitle>
              </DialogHeader>
              <div className="grid gap-3">
                <Input
                  name="url"
                  placeholder="https://example.com/index.xml"
                  value={url}
                  onChange={(e) => setUrl(e.target.value)}
                />
              </div>
              <DialogFooter>
                <DialogClose asChild>
                  <Button variant="outline">Cancel</Button>
                </DialogClose>
                <Button
                  type="submit"
                  disabled={saving}
                  onClick={() => {
                    setSaving(true);
                    fetch("/api/feeds", {
                      method: "POST",
                      headers: {
                        "content-type": "application/json",
                      },
                      body: JSON.stringify({
                        url,
                      }),
                    }).then((res) => {
                      setSaving(false);
                      setOpen(false);

                      if (res.status !== 200) {
                        toast.error("An error occurred while adding feed.");
                      }
                    });
                  }}
                >
                  {saving && <Loader2Icon className="animate-spin" />} Save
                </Button>
              </DialogFooter>
            </DialogContent>
          </Dialog>
        </div>
        {posts.length === 0 && (
          <div className="flex-1 flex flex-col justify-center">
            <h2 className="text-center">
              Nothing here. Add some feeds to get started.
            </h2>
          </div>
        )}
        {posts.map((post) => (
          <a key={post.id} href={post.url}>
            <div className="flex gap-2 m-4 p-1 rounded-sm hover:bg-neutral-800 transition-colors">
              {post.thumbnail && (
                <img
                  src={post.thumbnail}
                  alt=""
                  className="w-[120px] h-[120px] object-cover rounded-sm"
                />
              )}
              <div className="flex-1 overflow-hidden p-1">
                <div className="flex justify-between text-sm dark:text-gray-400">
                  <small>{feeds[post.feed_id].title}</small>
                  <small>{new Date(post.post_time).toDateString()}</small>
                </div>
                <h2 className="font-semibold">{post.title}</h2>
                {post.description && (
                  <div className="line-clamp-3 dark:text-gray-200">
                    {post.description}
                  </div>
                )}
              </div>
            </div>
          </a>
        ))}
      </div>
      <Toaster position="top-center" />
    </ThemeProvider>
  );
}
