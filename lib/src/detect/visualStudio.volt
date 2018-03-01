module detect.visualStudio;

version (Windows):

enum VisualStudioVersion
{
	Unknown,
	V2015,
	V2017
}

fn visualStudioVersionToString(ver: VisualStudioVersion) string
{
	final switch (ver) with (VisualStudioVersion) {
	case Unknown: return "unknown";
	case V2015:   return "2015";
	case V2017:   return "2017";
	}
}
